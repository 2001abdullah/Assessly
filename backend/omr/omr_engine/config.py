"""
Engine configuration.

Every number the OMR decision depends on lives here, so it can be tuned from the
Settings screen without touching code, and so a saved configuration fully
describes how a batch was graded.

The defaults were chosen against the synthetic corpus in ``tests/`` -- see
``docs/ACCURACY.md`` for the measured effect of each gate.
"""

from __future__ import annotations

from dataclasses import dataclass, asdict, field
from typing import Any, Dict


@dataclass
class EngineConfig:
    # ---------------------------------------------------------------- input #
    work_dpi: int = 200
    """Resolution of the canonical (perspective-corrected) working image.

    200 dpi puts a 1.5 mm-radius bubble at ~24 px across, which is comfortably
    above the ~12 px where fill measurement starts getting noisy, while keeping
    an A4 page at 1654x2339 -- small enough to process ~10 sheets/second/core.
    """

    max_input_pixels: int = 40_000_000
    """Reject absurdly large uploads before they hit memory."""

    # ------------------------------------------------------- page detection #
    detect_page: bool = True
    """Find the sheet against its background before looking for fiducials.

    Turn off for flatbed scans where the sheet already fills the frame.
    """
    page_min_area_frac: float = 0.18
    page_approx_epsilon: float = 0.02

    # ------------------------------------------------------------ fiducials #
    fiducial_search_mm: float = 14.0
    """Half-size of the local window searched around each expected corner."""
    fiducial_min_area_frac: float = 0.18
    fiducial_max_area_frac: float = 3.0
    fiducial_min_squareness: float = 0.55
    max_reprojection_error_px: float = 7.0
    """Above this mean corner residual the sheet is reported as misaligned."""

    # --------------------------------------------------------- timing marks #
    use_timing_marks: bool = True
    timing_search_mm: float = 3.2
    timing_min_hits_frac: float = 0.55
    """Fraction of timing marks that must be found before the per-row
    correction is trusted; below it the engine falls back to the plain
    fiducial homography."""
    timing_max_shift_mm: float = 2.0

    # ------------------------------------------------------------- sampling #
    sample_radius_frac: float = 0.82
    """Sampled disc radius as a fraction of the printed bubble radius.

    Keeps the printed outline out of the measurement while still covering the
    area a candidate actually shades in.  Measured optimum: accuracy degrades
    below ~0.78 (too little of a partial fill is seen) and above ~0.86 (the
    printed ring starts bleeding into the disc under blur).
    """

    # ------------------------------------------ pixel-level ink calibration #
    calibrate_ink: bool = True
    ink_level_default: float = 0.78
    """Fallback ink cut as a fraction of the paper level, used when the sheet
    has too few pixels for a reliable estimate."""
    ink_paper_bias: float = 0.20
    """Where the ink cut sits between the Otsu paper/ink midpoint (0.0) and the
    paper noise floor (1.0).  Higher sees lighter pencil but also picks up more
    of the printed bubble outline; 0.20 was the measured optimum -- see docs/ACCURACY.md."""
    ink_paper_tail_pct: float = 3.0
    """Percentile of the *paper* pixel population taken as the noise floor."""
    ink_margin: float = 4.0
    """Extra grey levels of headroom below that floor."""
    ink_level_min: float = 0.45
    ink_level_max: float = 0.93

    # ----------------------------------------- bubble-level fill thresholds #
    calibrate_fill: bool = True
    fill_threshold: float = 0.35
    """Fill score above which a bubble counts as marked (fallback / clamp centre)."""
    fill_bias: float = 0.32
    """Where the calibrated threshold sits between the empty level and the mark
    level on this sheet.  Low values favour catching light or partial fills;
    high values favour ignoring smudges.  0.32 was the accuracy optimum on the
    synthetic corpus."""
    fill_min_separation: float = 0.15
    """Minimum gap between the measured empty and mark levels before the
    calibration is trusted at all (an all-blank sheet has no gap)."""
    fill_calib_min: float = 0.16
    fill_calib_max: float = 0.62
    blank_ceiling: float = 0.15
    """A best-option score below this is confidently blank; between this and the
    threshold it is a *faint* mark and gets flagged for review."""

    # ----------------------------------------------------- ambiguity policy #
    runner_up_ratio: float = 0.45
    """Flag a multi-mark when the second bubble carries at least this fraction of
    the winner's fill, even if it sits below the mark threshold.

    This catches the partially-shaded-then-changed-answer case: a half-filled A
    beside a solid C is two bubbles with real ink in them, and which one the
    candidate meant is not the engine's call to make."""
    min_absolute_margin: float = 0.11
    """Minimum best-minus-second gap for a confident single answer."""
    multi_mark_policy: str = "ambiguous"
    """``ambiguous`` (flag for review), ``blank`` (treat as unanswered) or
    ``highest`` (take the darkest bubble)."""

    # --------------------------------------------------------- image quality #
    min_sharpness: float = 8.0
    """Variance of the Laplacian on the warped page; below this the image is
    too blurred to trust."""
    min_contrast: float = 0.10
    warn_sharpness: float = 25.0

    # ---------------------------------------------------------- confidence #
    conf_full_separation: float = 0.30
    conf_full_lift: float = 0.28
    review_confidence: float = 0.55
    """Sheets or fields below this land in the manual review queue."""

    # ------------------------------------------------------------ debugging #
    save_debug_overlay: bool = False

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "EngineConfig":
        known = {f for f in cls.__dataclass_fields__}  # type: ignore[attr-defined]
        return cls(**{k: v for k, v in (d or {}).items() if k in known})

    def validated(self) -> "EngineConfig":
        if not (72 <= self.work_dpi <= 600):
            raise ValueError("work_dpi must be between 72 and 600")
        if not (0.3 <= self.sample_radius_frac <= 1.0):
            raise ValueError("sample_radius_frac must be between 0.3 and 1.0")
        if self.multi_mark_policy not in {"ambiguous", "blank", "highest"}:
            raise ValueError("multi_mark_policy must be ambiguous|blank|highest")
        if not (0.0 <= self.blank_ceiling < self.fill_threshold <= 1.0):
            raise ValueError("require 0 <= blank_ceiling < fill_threshold <= 1")
        return self


DEFAULT_CONFIG = EngineConfig()
