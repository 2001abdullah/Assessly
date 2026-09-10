"""
Bubble measurement and the fill decision.

The measurement is deliberately boring and deterministic: for every bubble we
compute one number -- the fraction of sampled pixels that are darker than the
sheet's own ink level -- and every downstream decision is a comparison of those
numbers against thresholds the sheet itself calibrates.

Two calibrations run per sheet, both Otsu splits with a bimodality guard and a
hard clamp so a pathological sheet degrades to the configured defaults rather
than inventing a threshold:

1. **Ink level** (pixel scale).  Splits paper from graphite/ink using only
   pixels inside bubbles.  This is what makes a faint 2H pencil and a heavy
   black gel pen both read correctly.
2. **Fill level** (bubble scale).  Splits marked bubbles from empty ones using
   the distribution of fill scores across the whole sheet.  This absorbs
   whatever the candidate's shading habit is -- outline-only, hatched, or fully
   blacked in.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

import numpy as np

from .config import EngineConfig
from .detect import RowCorrection
from .imageops import disc_offsets, otsu_threshold
from .models import BLANK, FAINT, MARKED, MULTI, GroupReading
from .template import OMRTemplate


@dataclass
class Calibration:
    ink_threshold: float = 0.0
    ink_separability: float = 0.0
    ink_calibrated: bool = False
    paper_level: float = 235.0
    fill_threshold: float = 0.35
    fill_separability: float = 0.0
    fill_calibrated: bool = False
    empty_level: float = 0.0
    mark_level: float = 0.0
    marked_ratio: float = 0.0


@dataclass
class BubbleSamples:
    """Fill scores for every bubble on the sheet, indexed by group key."""

    scores: Dict[str, np.ndarray] = field(default_factory=dict)
    centres: Dict[str, np.ndarray] = field(default_factory=dict)
    radii: Dict[str, np.ndarray] = field(default_factory=dict)
    calibration: Calibration = field(default_factory=Calibration)


# --------------------------------------------------------------------------- #
# Sampling
# --------------------------------------------------------------------------- #


def _positions(template: OMRTemplate, k: float, rc: RowCorrection
               ) -> Tuple[np.ndarray, np.ndarray, np.ndarray, List[Tuple[str, int, int]]]:
    """Flatten every bubble to canonical pixel coordinates, row-corrected."""
    xs: List[float] = []
    ys: List[float] = []
    rs: List[float] = []
    ref: List[Tuple[str, int, int]] = []  # (group key, slot, running index)
    for g in template.groups:
        for si, b in enumerate(g.bubbles):
            xs.append(b.x_mm * k)
            ys.append(b.y_mm * k)
            rs.append(b.r_mm * k)
            ref.append((g.key, si, len(ref)))
    x = np.asarray(xs, dtype=np.float64)
    y = np.asarray(ys, dtype=np.float64)
    x, y = rc.apply(x, y)
    return x, y, np.asarray(rs, dtype=np.float64), ref


def _disc_pixel_index(canon: np.ndarray, cx: np.ndarray, cy: np.ndarray,
                      radius: float) -> np.ndarray:
    """(M, P) array of pixel values inside each bubble's sampling disc."""
    H, W = canon.shape[:2]
    off_y, off_x = disc_offsets(radius)
    iy = np.clip(np.rint(cy)[:, None].astype(np.int32) + off_y[None, :], 0, H - 1)
    ix = np.clip(np.rint(cx)[:, None].astype(np.int32) + off_x[None, :], 0, W - 1)
    return canon[iy, ix]


def sample_bubbles(canon: np.ndarray, template: OMRTemplate, k: float,
                   rc: RowCorrection, cfg: EngineConfig) -> BubbleSamples:
    """Measure every bubble on the canonical page."""
    x, y, r, ref = _positions(template, k, rc)
    sample_r = r * cfg.sample_radius_frac

    # Group bubbles by sampling radius so the disc offsets are computed once
    # per distinct size rather than once per bubble.
    rounded = np.rint(sample_r * 4.0) / 4.0
    patches: Dict[float, Tuple[np.ndarray, np.ndarray]] = {}
    for rv in np.unique(rounded):
        sel = np.flatnonzero(rounded == rv)
        patches[float(rv)] = (sel, _disc_pixel_index(canon, x[sel], y[sel], float(rv)))

    # -- stage 1: ink level ------------------------------------------------ #
    #
    # This stage is deliberately *inclusive*: its job is to answer "is this
    # pixel darker than clean paper?", not "is this bubble filled?".  Putting
    # the cut at the midpoint between paper and graphite (what a plain Otsu
    # split gives) throws away light pencil, because a 2H mark sits much closer
    # to paper than to a heavy ballpoint.  So the cut goes just *below the
    # darkest ordinary paper pixel* instead, and all of the actual
    # discrimination is left to the fill-fraction stage below, where the
    # per-sheet empty distribution is available to calibrate against.
    all_pixels = np.concatenate([p.ravel() for _, p in patches.values()])
    sample = all_pixels
    if sample.size > 400_000:  # neither Otsu nor a percentile needs every pixel
        sample = sample[:: int(sample.size // 400_000) + 1]
    sample = sample.astype(np.float64)

    paper = max(float(np.percentile(sample, 92.0)), 40.0)
    ink_thr = cfg.ink_level_default * paper
    sep = 0.0
    calibrated = False
    if cfg.calibrate_ink:
        t, sep = otsu_threshold(sample)
        paper_pixels = sample[sample > t] if np.isfinite(t) else sample[sample > 0.8 * paper]
        if np.isfinite(t) and paper_pixels.size >= 64:
            paper_low = float(np.percentile(paper_pixels, cfg.ink_paper_tail_pct)) - cfg.ink_margin
            # ``ink_paper_bias`` slides the cut between the Otsu midpoint (0.0,
            # crisp but blind to light pencil) and the paper noise floor (1.0,
            # sees everything but also sees the printed bubble ring).
            cand = t + cfg.ink_paper_bias * (paper_low - t)
            lo, hi = cfg.ink_level_min * paper, cfg.ink_level_max * paper
            ink_thr = float(np.clip(cand, lo, hi))
            calibrated = True

    # -- fill scores ------------------------------------------------------- #
    flat = np.zeros(len(ref), dtype=np.float64)
    for _, (sel, pix) in patches.items():
        flat[sel] = (pix < ink_thr).mean(axis=1)

    # -- stage 2: fill level ---------------------------------------------- #
    #
    # Rather than an Otsu split of the pooled scores, exploit the structure of
    # the sheet: within one question exactly one bubble is normally marked, so
    # the per-group *maximum* samples the mark population and the per-group
    # *median* samples the empty population.  That gives two clean level
    # estimates without depending on Otsu, which is degenerate here -- when
    # every mark is solid the score histogram is two spikes at 0 and 1 and any
    # cut between them is equally optimal, so Otsu returns an arbitrary one.
    q_groups = [g for g in template.groups if g.owner == "questions"]
    fill_thr = cfg.fill_threshold
    fsep = 0.0
    fcal = False
    empty_level = mark_level = 0.0
    if cfg.calibrate_fill and len(q_groups) >= 8:
        cursor_by_key: Dict[str, Tuple[int, int]] = {}
        pos = 0
        for g in template.groups:
            cursor_by_key[g.key] = (pos, pos + len(g.bubbles))
            pos += len(g.bubbles)

        maxima: List[float] = []
        others: List[float] = []
        for g in q_groups:
            a, b = cursor_by_key[g.key]
            vals = np.sort(flat[a:b])[::-1]
            if vals.size < 2:
                continue
            maxima.append(float(vals[0]))
            others.extend(float(v) for v in vals[1:])

        if maxima and others:
            mark_level = float(np.median(maxima))
            empty_level = float(np.median(others))
            empty_hi = float(np.percentile(others, 98.0))
            gap = mark_level - empty_level
            fsep = float(np.clip(gap, 0.0, 1.0))
            if gap >= cfg.fill_min_separation:
                thr = empty_level + cfg.fill_bias * gap
                # Lift the threshold clear of the empty population's own spread --
                # but never past the midpoint between the two levels.  The
                # "others" pool is only *mostly* empty bubbles: on a sheet where
                # many questions genuinely carry two marks, its upper tail is
                # made of real marks, and an uncapped floor would climb above
                # them and silently accept the double marks as single answers.
                floor = min(empty_hi + 0.03, empty_level + 0.5 * gap)
                fill_thr = float(np.clip(max(thr, floor),
                                         cfg.fill_calib_min, cfg.fill_calib_max))
                fcal = True

    q_slots = [i for (key, _, i) in ref if key.startswith("q")]
    q_scores = flat[q_slots] if q_slots else flat

    calib = Calibration(
        ink_threshold=ink_thr,
        ink_separability=sep,
        ink_calibrated=calibrated,
        paper_level=paper,
        fill_threshold=fill_thr,
        fill_separability=fsep,
        fill_calibrated=fcal,
        empty_level=empty_level,
        mark_level=mark_level,
        marked_ratio=float((q_scores > fill_thr).mean()) if q_scores.size else 0.0,
    )

    out = BubbleSamples(calibration=calib)
    cursor = 0
    for g in template.groups:
        n = len(g.bubbles)
        out.scores[g.key] = flat[cursor : cursor + n].copy()
        out.centres[g.key] = np.stack([x[cursor : cursor + n], y[cursor : cursor + n]], axis=1)
        out.radii[g.key] = r[cursor : cursor + n].copy()
        cursor += n
    return out


# --------------------------------------------------------------------------- #
# Decision
# --------------------------------------------------------------------------- #


def decide_group(key: str, kind: str, index: int, owner: str, labels: List[str],
                 scores: np.ndarray, fill_thr: float, cfg: EngineConfig) -> GroupReading:
    """Turn one group's fill scores into a reading with a status and confidence."""
    if scores.size == 0:
        return GroupReading(key, kind, index, owner, None, BLANK, 0.0, [], labels)

    order = np.argsort(scores)[::-1]
    i1 = int(order[0])
    s1 = float(scores[i1])
    s2 = float(scores[order[1]]) if scores.size > 1 else 0.0
    sep = s1 - s2
    lift = s1 - fill_thr

    # Keep the "confidently empty" ceiling below the calibrated mark threshold,
    # so a sheet that calibrates low still has a usable faint band.
    blank_ceiling = min(cfg.blank_ceiling, fill_thr * 0.55)

    def _pack(value: Optional[str], status: str, conf: float) -> GroupReading:
        return GroupReading(key, kind, index, owner, value, status,
                            float(np.clip(conf, 0.0, 1.0)),
                            [float(s) for s in scores], list(labels))

    if s1 < blank_ceiling:
        return _pack(None, BLANK, (fill_thr - s1) / max(fill_thr, 1e-6))

    if s1 < fill_thr:
        # Something is there but it is not a convincing mark: a partial fill, a
        # smudge, or an incompletely rubbed-out answer.  Propose it, flag it.
        return _pack(labels[i1], FAINT, 0.25 * (s1 - blank_ceiling) /
                     max(fill_thr - blank_ceiling, 1e-6))

    # A second bubble that clears the mark threshold is a double mark, full
    # stop -- no ratio test to soften it.  The threshold was already calibrated
    # to sit above this sheet's own empty population, so anything above it is
    # real ink the candidate put there, and guessing which one they meant is
    # exactly the silent error this system must not make.
    competing = (
        s2 >= fill_thr
        or s2 >= cfg.runner_up_ratio * s1
        or sep < cfg.min_absolute_margin
    )
    if competing:
        if cfg.multi_mark_policy == "highest":
            return _pack(labels[i1], MARKED, 0.30 * min(1.0, sep / max(cfg.min_absolute_margin, 1e-6)))
        if cfg.multi_mark_policy == "blank":
            return _pack(None, BLANK, 0.30)
        return _pack(None, MULTI, 0.15)

    conf = min(sep / cfg.conf_full_separation, 0.25 + lift / cfg.conf_full_lift)
    return _pack(labels[i1], MARKED, conf)


def read_groups(template: OMRTemplate, samples: BubbleSamples,
                cfg: EngineConfig) -> Dict[str, GroupReading]:
    """Decide every group on the sheet."""
    thr = samples.calibration.fill_threshold
    out: Dict[str, GroupReading] = {}
    for g in template.groups:
        out[g.key] = decide_group(
            g.key, g.kind, g.index, g.owner, g.labels,
            samples.scores.get(g.key, np.zeros(0)), thr, cfg,
        )
    return out
