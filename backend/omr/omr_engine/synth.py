"""
Synthetic sheet generation for testing and calibration.

Produces filled-in answer sheets with **known ground truth**, then damages them
the way a real capture does -- perspective, rotation, shadow, blur, sensor
noise, JPEG artefacts, low resolution, a cluttered desk background.  The test
suite grades the engine against these, so accuracy claims are measured rather
than asserted.

The clean page comes from the real generated PDF whenever a PDF rasteriser is
available, so the tests exercise the exact artefact an operator would print.  A
pure-OpenCV fallback keeps the suite runnable on machines without poppler.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Sequence, Set, Tuple

import cv2
import numpy as np

from .generator import generate_sheet_pdf
from .template import OMRTemplate

# --------------------------------------------------------------------------- #
# Ground truth
# --------------------------------------------------------------------------- #


@dataclass
class SheetSpec:
    """What a synthetic candidate wrote on the sheet."""

    roll: str = ""
    registration: str = ""
    answers: Dict[int, Optional[str]] = field(default_factory=dict)
    multi_marks: Dict[int, List[str]] = field(default_factory=dict)
    faint: Set[int] = field(default_factory=set)
    erased: Dict[int, str] = field(default_factory=dict)
    """question -> option that was marked then rubbed out (leaves a smudge)."""


@dataclass
class Degradation:
    """How badly the capture mangles the page."""

    rotation_deg: float = 0.0
    perspective: float = 0.0  # corner displacement as a fraction of page size
    blur_sigma: float = 0.0
    noise_sigma: float = 0.0
    jpeg_quality: int = 0  # 0 = no JPEG round trip
    shadow: float = 0.0  # 0..1 strength of a soft directional shadow
    vignette: float = 0.0
    brightness: float = 1.0
    target_width: int = 0  # 0 = keep resolution
    background: bool = False
    margin_frac: float = 0.06

    @staticmethod
    def pristine() -> "Degradation":
        return Degradation()

    @staticmethod
    def scanner() -> "Degradation":
        return Degradation(rotation_deg=0.4, blur_sigma=0.4, noise_sigma=2.0,
                           jpeg_quality=92, target_width=1700)

    @staticmethod
    def good_phone() -> "Degradation":
        return Degradation(rotation_deg=1.5, perspective=0.008, blur_sigma=0.7,
                           noise_sigma=4.0, jpeg_quality=88, shadow=0.15,
                           vignette=0.15, target_width=1600, background=True)

    @staticmethod
    def hard_phone() -> "Degradation":
        return Degradation(rotation_deg=6.0, perspective=0.030, blur_sigma=1.5,
                           noise_sigma=9.0, jpeg_quality=62, shadow=0.42,
                           vignette=0.32, brightness=0.82, target_width=1250,
                           background=True)

    @staticmethod
    def punishing() -> "Degradation":
        return Degradation(rotation_deg=9.0, perspective=0.045, blur_sigma=2.1,
                           noise_sigma=13.0, jpeg_quality=45, shadow=0.55,
                           vignette=0.42, brightness=0.72, target_width=1050,
                           background=True)


# --------------------------------------------------------------------------- #
# Clean page rendering
# --------------------------------------------------------------------------- #


def _have_pdftoppm() -> bool:
    return shutil.which("pdftoppm") is not None


def render_clean_page(template: OMRTemplate, dpi: int = 300) -> np.ndarray:
    """Render the template's printable PDF to a grayscale page image."""
    if _have_pdftoppm():
        tmp = tempfile.mkdtemp(prefix="omr_synth_")
        try:
            pdf = os.path.join(tmp, "sheet.pdf")
            generate_sheet_pdf(template, pdf)
            out = os.path.join(tmp, "page")
            subprocess.run(
                ["pdftoppm", "-r", str(dpi), "-gray", "-png", "-singlefile", pdf, out],
                check=True, capture_output=True,
            )
            img = cv2.imread(out + ".png", cv2.IMREAD_GRAYSCALE)
            if img is not None:
                return img
        except Exception:
            pass
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    return render_clean_page_cv(template, dpi)


def render_clean_page_cv(template: OMRTemplate, dpi: int = 300) -> np.ndarray:
    """Fallback renderer: draws the geometry directly, no PDF toolchain needed."""
    k = dpi / 25.4
    h = int(round(template.page_h_mm * k))
    w = int(round(template.page_w_mm * k))
    page = np.full((h, w), 255, np.uint8)

    for f in template.fiducials:
        half = f.size_mm / 2.0
        cv2.rectangle(
            page,
            (int((f.x_mm - half) * k), int((f.y_mm - half) * k)),
            (int((f.x_mm + half) * k), int((f.y_mm + half) * k)),
            0, -1,
        )
    for t in template.timing_tracks:
        for y in t.y_positions_mm:
            cv2.rectangle(
                page,
                (int((t.x_mm - t.w_mm / 2) * k), int((y - t.h_mm / 2) * k)),
                (int((t.x_mm + t.w_mm / 2) * k), int((y + t.h_mm / 2) * k)),
                0, -1,
            )
    for g in template.groups:
        for b in g.bubbles:
            cv2.circle(page, (int(b.x_mm * k), int(b.y_mm * k)),
                       int(round(b.r_mm * k)), 115, max(1, int(0.18 * k)), cv2.LINE_AA)
    # a dense block standing in for the QR, so the orientation test has a target
    qx, qy, qs = template.qr_x_mm, template.qr_y_mm, template.qr_size_mm
    block = np.random.RandomState(7).randint(0, 2, (12, 12)).astype(np.uint8) * 255
    block = cv2.resize(block, (int(qs * k), int(qs * k)), interpolation=cv2.INTER_NEAREST)
    page[int(qy * k) : int(qy * k) + block.shape[0],
         int(qx * k) : int(qx * k) + block.shape[1]] = block
    return page


# --------------------------------------------------------------------------- #
# Filling bubbles
# --------------------------------------------------------------------------- #


def _draw_mark(page: np.ndarray, cx: float, cy: float, r: float, rng: np.random.RandomState,
               style: str = "solid", darkness: Optional[int] = None) -> None:
    """Draw one hand-made pencil mark, imperfectly, the way a person would."""
    if darkness is None:
        darkness = int(rng.randint(28, 105))
    jx, jy = rng.uniform(-0.16, 0.16) * r, rng.uniform(-0.16, 0.16) * r
    cx, cy = cx + jx, cy + jy
    axes = (max(2, int(r * rng.uniform(0.80, 1.02))), max(2, int(r * rng.uniform(0.80, 1.02))))
    angle = rng.uniform(0, 180)
    layer = np.zeros(page.shape, np.uint8)

    if style == "solid":
        cv2.ellipse(layer, (int(cx), int(cy)), axes, angle, 0, 360, 255, -1, cv2.LINE_AA)
    elif style == "heavy":
        cv2.ellipse(layer, (int(cx), int(cy)), (axes[0] + 1, axes[1] + 1), angle,
                    0, 360, 255, -1, cv2.LINE_AA)
        darkness = int(rng.randint(10, 40))
    elif style == "scribble":
        step = max(2, int(r / 3.2))
        for off in range(-axes[1], axes[1], step):
            y = int(cy + off)
            dx = int((axes[0] ** 2 * max(0.0, 1 - (off / max(axes[1], 1)) ** 2)) ** 0.5)
            cv2.line(layer, (int(cx - dx), y), (int(cx + dx), y), 255,
                     max(1, int(r * 0.45)), cv2.LINE_AA)
    elif style == "partial":
        cv2.ellipse(layer, (int(cx), int(cy)), axes, angle, 0, 360, 255, -1, cv2.LINE_AA)
        cut = np.zeros_like(layer)
        frac = rng.uniform(0.45, 0.68)
        cv2.rectangle(cut, (0, 0), (page.shape[1], int(cy - axes[1] + 2 * axes[1] * frac)),
                      255, -1)
        layer = cv2.bitwise_and(layer, cut)
    elif style == "outline":
        cv2.ellipse(layer, (int(cx), int(cy)), axes, angle, 0, 360, 255,
                    max(1, int(r * 0.35)), cv2.LINE_AA)
    elif style == "light":
        cv2.ellipse(layer, (int(cx), int(cy)), axes, angle, 0, 360, 255, -1, cv2.LINE_AA)
        darkness = int(rng.randint(120, 168))
    elif style == "erased":
        # a rubbed-out answer leaves a real grey ghost, not a clean page
        cv2.ellipse(layer, (int(cx), int(cy)), axes, angle, 0, 360, 255, -1, cv2.LINE_AA)
        darkness = int(rng.randint(158, 205))
        layer = cv2.GaussianBlur(layer, (0, 0), max(1.0, r * 0.28))

    mask = layer > 0
    if not mask.any():
        return
    texture = rng.normal(0, 12, size=int(mask.sum())).astype(np.float32)
    vals = np.clip(darkness + texture, 0, 255)
    alpha = (layer[mask].astype(np.float32) / 255.0)
    page[mask] = np.clip(
        page[mask].astype(np.float32) * (1 - alpha) + vals * alpha, 0, 255
    ).astype(np.uint8)


def fill_sheet(clean: np.ndarray, template: OMRTemplate, spec: SheetSpec, dpi: int,
               rng: Optional[np.random.RandomState] = None,
               style_mix: Optional[Sequence[str]] = None) -> np.ndarray:
    """Return a copy of ``clean`` with ``spec``'s marks drawn on it."""
    rng = rng or np.random.RandomState(0)
    styles = list(style_mix or ["solid", "solid", "solid", "heavy", "scribble", "partial"])
    page = clean.copy()
    k = dpi / 25.4

    def mark(group_key: str, value: str, style: str = "") -> None:
        try:
            g = template.group(group_key)
        except KeyError:
            return
        for b in g.bubbles:
            if b.value == value:
                _draw_mark(page, b.x_mm * k, b.y_mm * k, b.r_mm * k, rng,
                           style or styles[rng.randint(len(styles))])
                return

    for fname, digits in (("roll", spec.roll), ("registration", spec.registration)):
        spec_field = template.fields.get(fname)
        if not spec_field or not digits:
            continue
        pad = spec_field.digits - len(digits)
        for i, ch in enumerate(digits):
            if pad + i < 0:
                continue
            mark(f"{fname}.d{pad + i}", ch, "solid")

    for q, opt in spec.answers.items():
        if opt is None:
            continue
        style = "light" if q in spec.faint else ""
        mark(f"q{q}", opt, style)
    for q, opts in spec.multi_marks.items():
        for opt in opts:
            mark(f"q{q}", opt, "solid")
    for q, opt in spec.erased.items():
        mark(f"q{q}", opt, "erased")
    return page


# --------------------------------------------------------------------------- #
# Degradation
# --------------------------------------------------------------------------- #


def _desk_background(h: int, w: int, rng: np.random.RandomState) -> np.ndarray:
    base = rng.randint(58, 118)
    bg = np.full((h, w), base, np.uint8)
    noise = rng.normal(0, 9, (h // 8 + 1, w // 8 + 1)).astype(np.float32)
    noise = cv2.resize(noise, (w, h), interpolation=cv2.INTER_LINEAR)
    bg = np.clip(bg.astype(np.float32) + noise, 0, 255).astype(np.uint8)
    for _ in range(rng.randint(2, 6)):  # a few desk objects / shadows
        x, y = rng.randint(0, w), rng.randint(0, h)
        cv2.circle(bg, (x, y), rng.randint(20, 120), int(rng.randint(30, 150)), -1)
    return cv2.GaussianBlur(bg, (0, 0), 6)


def degrade(page: np.ndarray, deg: Degradation,
            rng: Optional[np.random.RandomState] = None) -> np.ndarray:
    """Apply a capture-realistic degradation chain to a clean filled page."""
    rng = rng or np.random.RandomState(0)
    h, w = page.shape[:2]

    m = deg.margin_frac if deg.background else 0.02
    pad_x, pad_y = int(w * m), int(h * m)

    src = np.float32([[0, 0], [w, 0], [w, h], [0, h]])
    dst = np.float32([[pad_x, pad_y], [pad_x + w, pad_y],
                      [pad_x + w, pad_y + h], [pad_x, pad_y + h]])

    if deg.perspective > 0:
        jitter = deg.perspective * max(w, h)
        dst = dst + rng.uniform(-jitter, jitter, dst.shape).astype(np.float32)
    if abs(deg.rotation_deg) > 1e-6:
        centre = dst.mean(axis=0)
        th = np.radians(deg.rotation_deg)
        R = np.float32([[np.cos(th), -np.sin(th)], [np.sin(th), np.cos(th)]])
        dst = (dst - centre) @ R.T + centre

    # Grow the canvas so the whole transformed page stays in frame.  A sheet
    # with a corner outside the image is a *different* failure (the engine is
    # supposed to refuse those), so it must not leak into the degradation
    # fixtures by accident.
    shift = np.float32([max(0.0, pad_x - dst[:, 0].min()), max(0.0, pad_y - dst[:, 1].min())])
    dst = dst + shift
    canvas_w = int(np.ceil(dst[:, 0].max() + pad_x))
    canvas_h = int(np.ceil(dst[:, 1].max() + pad_y))
    canvas = (_desk_background(canvas_h, canvas_w, rng) if deg.background
              else np.full((canvas_h, canvas_w), 244, np.uint8))

    H = cv2.getPerspectiveTransform(src, dst)
    warped = cv2.warpPerspective(page, H, (canvas_w, canvas_h), flags=cv2.INTER_LINEAR,
                                 borderMode=cv2.BORDER_CONSTANT, borderValue=0)
    mask = cv2.warpPerspective(np.full((h, w), 255, np.uint8), H, (canvas_w, canvas_h),
                               flags=cv2.INTER_NEAREST, borderMode=cv2.BORDER_CONSTANT,
                               borderValue=0)
    # a soft drop shadow under the sheet keeps page detection honest
    if deg.background:
        sh = cv2.GaussianBlur(mask, (0, 0), 12)
        canvas = np.clip(canvas.astype(np.float32) * (1 - 0.35 * sh / 255.0),
                         0, 255).astype(np.uint8)
    img = np.where(mask > 127, warped, canvas).astype(np.uint8)

    img = img.astype(np.float32)
    # Illumination fields are inherently low-frequency, so they are built on a
    # small grid and scaled up -- identical result, ~50x cheaper than blurring
    # a full-resolution page with a several-hundred-pixel sigma.
    LOW = 96
    lw = LOW
    lh = max(8, int(LOW * canvas_h / max(canvas_w, 1)))
    if deg.shadow > 0:
        gx = np.linspace(0, 1, lw, dtype=np.float32)
        gy = np.linspace(0, 1, lh, dtype=np.float32)
        ang = rng.uniform(0, 2 * np.pi)
        grad = (np.cos(ang) * gx[None, :] + np.sin(ang) * gy[:, None])
        grad = (grad - grad.min()) / max(float(np.ptp(grad)), 1e-6)
        blob = np.zeros((lh, lw), np.float32)
        cv2.circle(blob, (int(rng.uniform(0.1, 0.9) * lw), int(rng.uniform(0.1, 0.9) * lh)),
                   int(0.45 * max(lh, lw)), 1.0, -1)
        blob = cv2.GaussianBlur(blob, (0, 0), 0.16 * max(lh, lw))
        field_low = 1.0 - deg.shadow * (0.55 * grad + 0.45 * blob)
        img *= cv2.resize(field_low, (canvas_w, canvas_h), interpolation=cv2.INTER_LINEAR)
    if deg.vignette > 0:
        yy, xx = np.mgrid[0:lh, 0:lw].astype(np.float32)
        r = np.sqrt(((xx / lw - 0.5) ** 2 + (yy / lh - 0.5) ** 2) * 2)
        vig = 1.0 - deg.vignette * np.clip(r, 0, 1) ** 2
        img *= cv2.resize(vig, (canvas_w, canvas_h), interpolation=cv2.INTER_LINEAR)
    img *= deg.brightness
    img = np.clip(img, 0, 255)

    if deg.blur_sigma > 0:
        img = cv2.GaussianBlur(img, (0, 0), deg.blur_sigma)
    if deg.noise_sigma > 0:
        img = img + rng.normal(0, deg.noise_sigma, img.shape)
    img = np.clip(img, 0, 255).astype(np.uint8)

    if deg.target_width and deg.target_width < img.shape[1]:
        s = deg.target_width / img.shape[1]
        img = cv2.resize(img, None, fx=s, fy=s, interpolation=cv2.INTER_AREA)
    if deg.jpeg_quality:
        ok, buf = cv2.imencode(".jpg", img, [int(cv2.IMWRITE_JPEG_QUALITY),
                                             int(deg.jpeg_quality)])
        if ok:
            img = cv2.imdecode(buf, cv2.IMREAD_GRAYSCALE)
    return cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)


# --------------------------------------------------------------------------- #
# Corpus helpers
# --------------------------------------------------------------------------- #


def random_spec(template: OMRTemplate, rng: np.random.RandomState,
                blank_rate: float = 0.03, multi_rate: float = 0.0,
                faint_rate: float = 0.0, erase_rate: float = 0.0,
                roll: Optional[str] = None,
                registration: Optional[str] = None) -> SheetSpec:
    """A plausible candidate: mostly answered, with a realistic sprinkle of mess."""
    labels = template.option_labels
    rd = template.fields["roll"].digits
    gd = template.fields["registration"].digits if "registration" in template.fields else 0
    spec = SheetSpec(
        roll=roll or "".join(str(rng.randint(10)) for _ in range(rd)),
        registration=(registration if registration is not None
                      else "".join(str(rng.randint(10)) for _ in range(gd))),
    )
    for q in range(1, template.num_questions + 1):
        u = rng.rand()
        if u < blank_rate:
            spec.answers[q] = None
            continue
        opt = labels[rng.randint(len(labels))]
        spec.answers[q] = opt
        if rng.rand() < multi_rate:
            others = [l for l in labels if l != opt]
            spec.multi_marks[q] = [others[rng.randint(len(others))]]
        elif rng.rand() < faint_rate:
            spec.faint.add(q)
        elif rng.rand() < erase_rate:
            others = [l for l in labels if l != opt]
            spec.erased[q] = others[rng.randint(len(others))]
    return spec


def make_sheet_image(template: OMRTemplate, spec: SheetSpec, deg: Degradation,
                     dpi: int = 300, seed: int = 0,
                     clean: Optional[np.ndarray] = None) -> np.ndarray:
    """Render + fill + degrade in one call."""
    rng = np.random.RandomState(seed)
    base = clean if clean is not None else render_clean_page(template, dpi)
    filled = fill_sheet(base, template, spec, dpi, rng)
    return degrade(filled, deg, rng)
