"""
End-to-end OMR processing: an image in, a :class:`SheetScan` out.

This module is the only thing the API, the CLI and the batch worker need to
import.  It has no knowledge of databases, HTTP or the UI.
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Union

import cv2
import numpy as np

from .bubbles import BubbleSamples, read_groups, sample_bubbles
from .config import DEFAULT_CONFIG, EngineConfig
from .decode import decode_field
from .detect import Alignment, RowCorrection, align_sheet, measure_timing, skew_degrees
from .imageops import ArrayLike, contrast, load_image, sharpness
from .models import (
    AMBIGUOUS_STATUSES,
    FieldReading,
    GroupReading,
    QualityReport,
    SheetScan,
)
from .template import OMRTemplate


@dataclass
class ProcessDetail:
    """Intermediate artefacts kept for the debug overlay and manual review."""

    alignment: Optional[Alignment] = None
    samples: Optional[BubbleSamples] = None
    readings: Optional[Dict[str, GroupReading]] = None


class OMRProcessor:
    """
    Reusable processor bound to one template and configuration.

    Construct once per batch; :meth:`process` is stateless per image and safe to
    call from a worker process.
    """

    def __init__(self, template: OMRTemplate, config: Optional[EngineConfig] = None):
        self.template = template
        self.cfg = (config or DEFAULT_CONFIG).validated()

    # ------------------------------------------------------------------ API #
    def process(
        self,
        src: ArrayLike,
        source_name: str = "",
        debug_path: Optional[str] = None,
        return_detail: bool = False,
    ) -> Union[SheetScan, tuple]:
        t0 = time.perf_counter()
        detail = ProcessDetail()
        scan = SheetScan(ok=False, template_id=self.template.template_id, source=source_name)

        try:
            img = load_image(src, max_pixels=self.cfg.max_input_pixels)
        except Exception as exc:
            scan.errors.append(f"could not read image: {exc}")
            scan.needs_review = True
            scan.elapsed_ms = (time.perf_counter() - t0) * 1000.0
            return (scan, detail) if return_detail else scan

        align = align_sheet(img, self.template, self.cfg)
        detail.alignment = align
        scan.warnings.extend(align.warnings)

        if not align.ok:
            scan.errors.extend(align.errors)
            scan.needs_review = True
            scan.quality = QualityReport(
                sharpness=sharpness(cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)),
                fiducials_found=len(align.fiducials),
                grade="poor",
                score=0.0,
            )
            scan.elapsed_ms = (time.perf_counter() - t0) * 1000.0
            return (scan, detail) if return_detail else scan

        canon = align.canonical
        k = align.k

        sharp = sharpness(canon)
        cont = contrast(canon)

        # Timing marks were already located and verified during alignment, so
        # sampling happens once, directly on the row-corrected coordinates.
        rc = align.row_correction
        samples = sample_bubbles(canon, self.template, k, rc, self.cfg)
        detail.samples = samples

        readings = read_groups(self.template, samples, self.cfg)
        detail.readings = readings

        roll = decode_field(self.template, "roll", readings, self.cfg)
        reg = (
            decode_field(self.template, "registration", readings, self.cfg)
            if "registration" in self.template.fields
            else FieldReading("registration", None, [], [], 1.0, False, "not on template")
        )

        answers: List[GroupReading] = sorted(
            (r for r in readings.values() if r.owner == "questions"), key=lambda r: r.index
        )

        quality = self._quality(align, rc, samples, sharp, cont, answers)
        scan.quality = quality
        scan.roll = roll
        scan.registration = reg
        scan.answers = answers
        scan.qr_payload = self._read_qr(canon, k)
        scan.ok = True

        # ---- gates: never let a doubtful sheet through silently ---------- #
        if sharp < self.cfg.min_sharpness:
            scan.warnings.append(
                f"image is blurred (sharpness {sharp:.1f} < {self.cfg.min_sharpness})"
            )
            scan.needs_review = True
        elif sharp < self.cfg.warn_sharpness:
            scan.warnings.append(f"image is soft (sharpness {sharp:.1f})")
        if cont < self.cfg.min_contrast:
            scan.warnings.append(f"very low contrast ({cont:.2f})")
            scan.needs_review = True
        if rc.active and rc.rms_px > self.cfg.max_reprojection_error_px:
            scan.warnings.append(
                f"sheet alignment is poor (row residual {rc.rms_px:.1f}px)"
            )
            scan.needs_review = True
        if self.cfg.use_timing_marks and not rc.active:
            scan.warnings.append(
                "timing marks not readable; using corner registration only"
            )
        if roll.needs_review or roll.value is None:
            scan.warnings.append(f"roll number needs verification: {roll.note or 'unclear'}")
            scan.needs_review = True
        if "registration" in self.template.fields and (reg.needs_review or reg.value is None):
            scan.warnings.append(
                f"registration number needs verification: {reg.note or 'unclear'}"
            )
            scan.needs_review = True

        amb = [a.index for a in answers if a.status in AMBIGUOUS_STATUSES]
        if amb:
            preview = ", ".join(map(str, amb[:8])) + (" ..." if len(amb) > 8 else "")
            scan.warnings.append(f"{len(amb)} question(s) need verification: {preview}")
            scan.needs_review = True
        if quality.grade == "poor":
            scan.needs_review = True

        if debug_path:
            try:
                from .debug import render_overlay

                render_overlay(canon, self.template, samples, readings, rc, k, debug_path)
                scan.debug_image_path = debug_path
            except Exception as exc:  # pragma: no cover - debugging is optional
                scan.warnings.append(f"debug overlay failed: {exc}")

        scan.elapsed_ms = (time.perf_counter() - t0) * 1000.0
        return (scan, detail) if return_detail else scan

    # -------------------------------------------------------------- helpers #
    def _quality(self, align: Alignment, rc: RowCorrection, samples: BubbleSamples,
                 sharp: float, cont: float, answers: List[GroupReading]) -> QualityReport:
        cfg = self.cfg
        # Normalise against a good-scan reference rather than the warn floor, so
        # the score keeps discriminating above "not blurred enough to reject".
        sharp_s = float(np.clip(sharp / max(10.0 * cfg.warn_sharpness, 1e-6), 0.0, 1.0))
        cont_s = float(np.clip(cont / 0.45, 0.0, 1.0))
        if rc.active:
            reg_s = float(np.clip(1.0 - rc.rms_px / max(cfg.max_reprojection_error_px, 1e-6),
                                  0.0, 1.0))
            timing_s = rc.found / max(rc.expected, 1)
        else:
            reg_s, timing_s = 0.55, 0.0
        amb_rate = (len([a for a in answers if a.status in AMBIGUOUS_STATUSES])
                    / max(len(answers), 1))
        amb_s = float(np.clip(1.0 - amb_rate * 6.0, 0.0, 1.0))
        sep_s = float(np.clip(samples.calibration.fill_separability / 0.8, 0.0, 1.0))

        score = (0.24 * sharp_s + 0.16 * cont_s + 0.24 * reg_s
                 + 0.10 * timing_s + 0.16 * amb_s + 0.10 * sep_s)
        grade = ("excellent" if score >= 0.85 else
                 "good" if score >= 0.70 else
                 "fair" if score >= 0.50 else "poor")

        return QualityReport(
            sharpness=sharp,
            contrast=cont,
            reprojection_error_px=rc.rms_px if rc.active else 0.0,
            fiducials_found=len(align.fiducials),
            timing_marks_found=rc.found,
            timing_marks_expected=rc.expected,
            ink_threshold=samples.calibration.ink_threshold,
            fill_threshold=samples.calibration.fill_threshold,
            skew_deg=skew_degrees(align.fiducials),
            grade=grade,
            score=score,
        )

    def _read_qr(self, canon: np.ndarray, k: float) -> str:
        t = self.template
        try:
            pad = int(3 * k)
            x0 = max(0, int(t.qr_x_mm * k) - pad)
            y0 = max(0, int(t.qr_y_mm * k) - pad)
            x1 = min(canon.shape[1], int((t.qr_x_mm + t.qr_size_mm) * k) + pad)
            y1 = min(canon.shape[0], int((t.qr_y_mm + t.qr_size_mm) * k) + pad)
            crop = canon[y0:y1, x0:x1]
            if crop.size == 0:
                return ""
            crop = cv2.resize(crop, None, fx=3.0, fy=3.0, interpolation=cv2.INTER_CUBIC)
            data, _, _ = cv2.QRCodeDetector().detectAndDecode(crop)
            return data or ""
        except Exception:
            return ""


def process_image(src: ArrayLike, template: OMRTemplate,
                  config: Optional[EngineConfig] = None,
                  source_name: str = "", debug_path: Optional[str] = None) -> SheetScan:
    """One-shot convenience wrapper around :class:`OMRProcessor`."""
    return OMRProcessor(template, config).process(  # type: ignore[return-value]
        src, source_name=source_name, debug_path=debug_path
    )
