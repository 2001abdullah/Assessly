"""
Sheet detection and geometric registration.

Pipeline implemented here::

    photo ──► page quad (coarse)  ──► fiducial refinement (exact corners)
          ──► homography mm→px    ──► warp to canonical page
          ──► orientation check   ──► timing-mark row correction

The canonical page is a fronto-parallel image of the sheet at
``cfg.work_dpi``, where page millimetre ``(x, y)`` maps to pixel
``(x * k, y * k)`` with ``k = dpi / 25.4``.  Every later stage works purely in
that space, which is why the sampling code never has to think about perspective.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Sequence, Tuple

import cv2
import numpy as np

from .config import EngineConfig
from .imageops import (
    apply_h,
    flat_field,
    homography_scale,
    largest_dark_blob_centroid,
    mm_to_px_matrix,
    order_quad,
    to_gray,
)
from .template import OMRTemplate

CORNER_ORDER = ("tl", "tr", "br", "bl")


# --------------------------------------------------------------------------- #
# Coarse page detection
# --------------------------------------------------------------------------- #


def find_page_quad(gray: np.ndarray, cfg: EngineConfig) -> Optional[np.ndarray]:
    """
    Locate the sheet's outline in a photograph.

    Two strategies are tried: brightness segmentation (the paper is lighter than
    whatever it is lying on) and edge detection.  Either way the result is the
    largest convex 4-gon covering a plausible share of the frame.
    """
    h, w = gray.shape[:2]
    scale = 900.0 / max(h, w)
    small = cv2.resize(gray, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA) \
        if scale < 1.0 else gray.copy()
    sh, sw = small.shape[:2]
    frame_area = float(sh * sw)
    blurred = cv2.GaussianBlur(small, (5, 5), 0)

    candidates: List[np.ndarray] = []

    # -- strategy 1: bright-paper segmentation --------------------------- #
    _, th = cv2.threshold(blurred, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    th = cv2.morphologyEx(th, cv2.MORPH_CLOSE,
                          cv2.getStructuringElement(cv2.MORPH_RECT, (9, 9)))
    candidates.extend(_quads_from_mask(th, frame_area, cfg))

    # -- strategy 2: edges ------------------------------------------------ #
    edges = cv2.Canny(blurred, 40, 130)
    edges = cv2.dilate(edges, np.ones((3, 3), np.uint8), iterations=2)
    candidates.extend(_quads_from_mask(edges, frame_area, cfg))

    if not candidates:
        return None
    best = max(candidates, key=lambda q: cv2.contourArea(q))
    if scale < 1.0:
        best = best / scale
    return order_quad(best)


def _quads_from_mask(mask: np.ndarray, frame_area: float,
                     cfg: EngineConfig) -> List[np.ndarray]:
    cnts, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    out: List[np.ndarray] = []
    for c in sorted(cnts, key=cv2.contourArea, reverse=True)[:8]:
        area = cv2.contourArea(c)
        if area < cfg.page_min_area_frac * frame_area:
            continue
        peri = cv2.arcLength(c, True)
        approx = cv2.approxPolyDP(c, cfg.page_approx_epsilon * peri, True)
        if len(approx) == 4 and cv2.isContourConvex(approx):
            out.append(approx.reshape(4, 2).astype(np.float32))
        else:
            rect = cv2.minAreaRect(c)
            box = cv2.boxPoints(rect).astype(np.float32)
            # only accept the bounding box when the contour really fills it
            if area > 0.80 * abs(rect[1][0] * rect[1][1]):
                out.append(box)
    return out


# --------------------------------------------------------------------------- #
# Fiducials
# --------------------------------------------------------------------------- #


@dataclass
class FiducialHit:
    name: str
    x: float
    y: float
    area: float
    squareness: float
    confident: bool


def _search_fiducial(
    gray: np.ndarray,
    centre: Tuple[float, float],
    half_px: float,
    expected_area: float,
    cfg: EngineConfig,
    name: str,
) -> Optional[FiducialHit]:
    h, w = gray.shape[:2]
    cx, cy = centre
    x0 = int(max(0, round(cx - half_px)))
    y0 = int(max(0, round(cy - half_px)))
    x1 = int(min(w, round(cx + half_px)))
    y1 = int(min(h, round(cy + half_px)))
    if x1 - x0 < 8 or y1 - y0 < 8:
        return None
    win = gray[y0:y1, x0:x1]

    thr, _ = cv2.threshold(cv2.GaussianBlur(win, (3, 3), 0), 0, 255,
                           cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    _, bw = cv2.threshold(win, thr, 255, cv2.THRESH_BINARY_INV)
    bw = cv2.morphologyEx(bw, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))

    n, labels, stats, cents = cv2.connectedComponentsWithStats(bw, connectivity=8)
    best: Optional[FiducialHit] = None
    best_score = -1e9
    wh, ww = win.shape[:2]
    for i in range(1, n):
        area = float(stats[i, cv2.CC_STAT_AREA])
        if area < expected_area * cfg.fiducial_min_area_frac:
            continue
        if area > expected_area * cfg.fiducial_max_area_frac:
            continue
        bx, by = stats[i, cv2.CC_STAT_LEFT], stats[i, cv2.CC_STAT_TOP]
        bwid, bhei = stats[i, cv2.CC_STAT_WIDTH], stats[i, cv2.CC_STAT_HEIGHT]
        if bwid < 3 or bhei < 3:
            continue
        squareness = area / float(bwid * bhei)
        aspect = bwid / float(bhei)
        if squareness < cfg.fiducial_min_squareness or not (0.55 <= aspect <= 1.8):
            continue
        touches = bx <= 0 or by <= 0 or bx + bwid >= ww - 1 or by + bhei >= wh - 1
        ccx, ccy = float(cents[i][0]), float(cents[i][1])
        dist = ((ccx - (cx - x0)) ** 2 + (ccy - (cy - y0)) ** 2) ** 0.5
        # prefer square, near the expected centre, of the expected size, not clipped
        score = (
            squareness * 2.0
            - abs(np.log(max(area, 1.0) / max(expected_area, 1.0))) * 1.2
            - (dist / max(half_px, 1.0)) * 1.5
            - (2.5 if touches else 0.0)
        )
        if score > best_score:
            best_score = score
            best = FiducialHit(name, x0 + ccx, y0 + ccy, area, squareness,
                               confident=not touches and score > -0.6)
    return best


def locate_fiducials(
    gray: np.ndarray, template: OMRTemplate, H0: np.ndarray, cfg: EngineConfig
) -> Dict[str, FiducialHit]:
    """Refine each corner by searching a local window around its projection."""
    scale = homography_scale(H0)  # px per mm
    half_px = cfg.fiducial_search_mm * scale
    hits: Dict[str, FiducialHit] = {}
    for name in CORNER_ORDER:
        f = template.fiducial(name)
        proj = apply_h(H0, np.array([[f.x_mm, f.y_mm]]))[0]
        expected_area = (f.size_mm * scale) ** 2
        hit = _search_fiducial(gray, (proj[0], proj[1]), half_px, expected_area, cfg, name)
        if hit is not None:
            hits[name] = hit
    return hits


def hunt_fiducials(
    gray: np.ndarray, template: OMRTemplate, cfg: EngineConfig
) -> Dict[str, FiducialHit]:
    """
    Global fallback: find every square-ish dark blob of a plausible size and keep
    the four that sit furthest into the corners.

    Used when page detection fails outright (e.g. white sheet on a white desk).
    """
    h, w = gray.shape[:2]
    k_est = min(w / template.page_w_mm, h / template.page_h_mm)
    size_px = template.fiducials[0].size_mm * k_est
    expected_area = size_px * size_px

    norm = flat_field(gray)
    _, bw = cv2.threshold(norm, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    bw = cv2.morphologyEx(bw, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    n, labels, stats, cents = cv2.connectedComponentsWithStats(bw, connectivity=8)

    cands: List[Tuple[float, float, float]] = []
    for i in range(1, n):
        area = float(stats[i, cv2.CC_STAT_AREA])
        if not (expected_area * 0.12 <= area <= expected_area * 5.0):
            continue
        bwid, bhei = stats[i, cv2.CC_STAT_WIDTH], stats[i, cv2.CC_STAT_HEIGHT]
        if bwid < 4 or bhei < 4:
            continue
        if area / float(bwid * bhei) < 0.60:
            continue
        if not (0.6 <= bwid / float(bhei) <= 1.7):
            continue
        cx, cy = float(cents[i][0]), float(cents[i][1])
        # fiducials live near the border
        if not (cx < 0.34 * w or cx > 0.66 * w) or not (cy < 0.34 * h or cy > 0.66 * h):
            continue
        cands.append((cx, cy, area))

    if len(cands) < 4:
        return {}

    pts = np.array([[c[0], c[1]] for c in cands], dtype=np.float64)
    s, d = pts[:, 0] + pts[:, 1], pts[:, 0] - pts[:, 1]
    picks = {
        "tl": int(np.argmin(s)),
        "br": int(np.argmax(s)),
        "tr": int(np.argmax(d)),
        "bl": int(np.argmin(d)),
    }
    if len(set(picks.values())) != 4:
        return {}
    return {
        name: FiducialHit(name, float(pts[i][0]), float(pts[i][1]), cands[i][2], 1.0, True)
        for name, i in picks.items()
    }


# --------------------------------------------------------------------------- #
# Timing-mark row correction
# --------------------------------------------------------------------------- #


@dataclass
class RowCorrection:
    """
    Per-row local warp derived from the printed timing marks.

    The fiducial homography gets the page globally right; the timing marks then
    absorb what a homography structurally cannot: printer scaling, paper stretch
    and gentle page curl.  For any point we linearly interpolate the measured
    left/right mark offsets vertically between the bracketing rows and
    horizontally between the two tracks.
    """

    row_y: np.ndarray = field(default_factory=lambda: np.zeros(0))
    left_x: float = 0.0
    right_x: float = 0.0
    dx_left: np.ndarray = field(default_factory=lambda: np.zeros(0))
    dy_left: np.ndarray = field(default_factory=lambda: np.zeros(0))
    dx_right: np.ndarray = field(default_factory=lambda: np.zeros(0))
    dy_right: np.ndarray = field(default_factory=lambda: np.zeros(0))
    found: int = 0
    expected: int = 0
    rms_px: float = 0.0
    active: bool = False

    def apply(self, x: np.ndarray, y: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
        if not self.active or self.row_y.size == 0:
            return x, y
        yy = np.clip(y, self.row_y[0], self.row_y[-1])
        dxl = np.interp(yy, self.row_y, self.dx_left)
        dyl = np.interp(yy, self.row_y, self.dy_left)
        dxr = np.interp(yy, self.row_y, self.dx_right)
        dyr = np.interp(yy, self.row_y, self.dy_right)
        span = max(self.right_x - self.left_x, 1e-6)
        t = np.clip((x - self.left_x) / span, -0.15, 1.15)
        return x + dxl + t * (dxr - dxl), y + dyl + t * (dyr - dyl)


def measure_timing(
    canon: np.ndarray, template: OMRTemplate, k: float, ink_thresh: int, cfg: EngineConfig
) -> RowCorrection:
    """Find every timing mark in the canonical page and build the row correction."""
    tracks = {t.name: t for t in template.timing_tracks}
    left, right = tracks.get("left"), tracks.get("right")
    if left is None or right is None or not left.y_positions_mm:
        return RowCorrection()

    rows = np.array(left.y_positions_mm, dtype=np.float64) * k
    n = len(rows)
    search_y = cfg.timing_search_mm * k
    max_shift = cfg.timing_max_shift_mm * k

    def scan(track) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
        cx = track.x_mm * k
        half_w = max(4.0, track.w_mm * k * 1.5)
        dxs = np.full(n, np.nan)
        dys = np.full(n, np.nan)
        ok = np.zeros(n, dtype=bool)
        H, W = canon.shape[:2]
        expected_area = (track.w_mm * k) * (track.h_mm * k)
        for i, cy in enumerate(rows):
            x0, x1 = int(max(0, cx - half_w)), int(min(W, cx + half_w))
            y0, y1 = int(max(0, cy - search_y)), int(min(H, cy + search_y))
            if x1 - x0 < 4 or y1 - y0 < 4:
                continue
            res = largest_dark_blob_centroid(canon[y0:y1, x0:x1], ink_thresh,
                                             min_area=max(4, int(expected_area * 0.20)))
            if res is None:
                continue
            bx, by, area = res
            if area > expected_area * 4.0:
                continue
            dx, dy = (x0 + bx) - cx, (y0 + by) - cy
            if abs(dx) > max_shift or abs(dy) > max_shift:
                continue
            dxs[i], dys[i], ok[i] = dx, dy, True
        return dxs, dys, ok

    dxl, dyl, okl = scan(left)
    dxr, dyr, okr = scan(right)

    found = int(okl.sum() + okr.sum())
    expected = 2 * n
    rc = RowCorrection(
        row_y=rows,
        left_x=left.x_mm * k,
        right_x=right.x_mm * k,
        found=found,
        expected=expected,
    )
    if expected == 0 or found < cfg.timing_min_hits_frac * expected:
        return rc

    rc.dx_left = _fill_gaps(dxl, okl)
    rc.dy_left = _fill_gaps(dyl, okl)
    rc.dx_right = _fill_gaps(dxr, okr)
    rc.dy_right = _fill_gaps(dyr, okr)
    resid = np.concatenate([dyl[okl], dyr[okr]]) if found else np.zeros(1)
    rc.rms_px = float(np.sqrt(np.mean(resid ** 2))) if resid.size else 0.0
    rc.active = True
    return rc


def _fill_gaps(values: np.ndarray, ok: np.ndarray) -> np.ndarray:
    """Interpolate missing timing marks from their neighbours."""
    out = values.astype(np.float64).copy()
    idx = np.arange(out.size)
    if ok.sum() == 0:
        return np.zeros_like(out)
    out[~ok] = np.interp(idx[~ok], idx[ok], out[ok])
    return out


# --------------------------------------------------------------------------- #
# Orientation
# --------------------------------------------------------------------------- #


def is_upside_down(canon: np.ndarray, template: OMRTemplate, k: float) -> bool:
    """
    Decide whether the sheet was fed in rotated by 180 degrees.

    The four fiducials are symmetric, so they cannot tell us which way up the
    page is.  The QR block can: it is a dense patch of ink in one specific
    corner, and the diagonally opposite region of a correctly-oriented sheet is
    almost pure white.  Comparing ink density between the two settles it without
    needing to decode anything.
    """
    H, W = canon.shape[:2]
    pad = 1.0 * k
    x0 = int(max(0, template.qr_x_mm * k - pad))
    y0 = int(max(0, template.qr_y_mm * k - pad))
    x1 = int(min(W, (template.qr_x_mm + template.qr_size_mm) * k + pad))
    y1 = int(min(H, (template.qr_y_mm + template.qr_size_mm) * k + pad))
    if x1 - x0 < 6 or y1 - y0 < 6:
        return False
    up = canon[y0:y1, x0:x1]
    down = canon[H - y1 : H - y0, W - x1 : W - x0]
    if up.size == 0 or down.size == 0:
        return False
    ink_up = float((up < 128).mean())
    ink_down = float((down < 128).mean())
    return ink_down > ink_up + 0.06


# --------------------------------------------------------------------------- #
# Top-level alignment
# --------------------------------------------------------------------------- #


@dataclass
class Alignment:
    ok: bool
    canonical: np.ndarray  # flat-fielded grayscale canonical page
    raw_canonical: np.ndarray  # canonical page before flat-fielding
    k: float  # canonical pixels per millimetre
    H: Optional[np.ndarray] = None  # page mm -> source image px
    fiducials: Dict[str, FiducialHit] = field(default_factory=dict)
    rotated_180: bool = False
    row_correction: RowCorrection = field(default_factory=RowCorrection)
    errors: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    method: str = ""


def _page_corner_homography(template: OMRTemplate, quad: np.ndarray) -> np.ndarray:
    src = np.array(
        [[0.0, 0.0], [template.page_w_mm, 0.0],
         [template.page_w_mm, template.page_h_mm], [0.0, template.page_h_mm]],
        dtype=np.float32,
    )
    return cv2.getPerspectiveTransform(src, quad.astype(np.float32))


def _identity_frame_homography(template: OMRTemplate, shape: Tuple[int, int]) -> np.ndarray:
    h, w = shape[:2]
    src = np.array(
        [[0.0, 0.0], [template.page_w_mm, 0.0],
         [template.page_w_mm, template.page_h_mm], [0.0, template.page_h_mm]],
        dtype=np.float32,
    )
    dst = np.array([[0, 0], [w, 0], [w, h], [0, h]], dtype=np.float32)
    return cv2.getPerspectiveTransform(src, dst)


def _fiducial_homography(template: OMRTemplate, hits: Dict[str, FiducialHit]) -> np.ndarray:
    src = np.array(
        [[template.fiducial(n).x_mm, template.fiducial(n).y_mm] for n in CORNER_ORDER],
        dtype=np.float32,
    )
    dst = np.array([[hits[n].x, hits[n].y] for n in CORNER_ORDER], dtype=np.float32)
    return cv2.getPerspectiveTransform(src, dst)


def estimate_ink_level(canon: np.ndarray) -> int:
    """
    A conservative ink cut for finding solid black marks (fiducials, timing).

    Timing marks are printed solid, so anything between roughly 0.4 and 0.8 of
    the paper level separates them; taking 0.6 of a robust paper estimate is
    stable even on a badly lit page.
    """
    paper = float(np.percentile(canon, 92.0))
    return int(np.clip(0.60 * max(paper, 40.0), 25, 210))


def _sheet_in_frame(hits: Dict[str, FiducialHit], shape: Tuple[int, int],
                    margin: float = 2.0) -> bool:
    h, w = shape[:2]
    return all(margin <= hit.x <= w - margin and margin <= hit.y <= h - margin
               for hit in hits.values())


def align_sheet(img_bgr: np.ndarray, template: OMRTemplate,
                cfg: EngineConfig) -> Alignment:
    """
    Register ``img_bgr`` against ``template`` and return the canonical page.

    Registration is *verified*, not assumed.  Four corner blobs can always be
    found somewhere, and a homography built from the wrong four produces a
    page-shaped image full of confident nonsense.  The printed timing marks are
    the independent check: they only fall where the model predicts when the
    model is actually right, so a low timing lock rate fails the sheet instead
    of grading it.  The marks are symmetric under a 180-degree flip, which
    conveniently lets us validate geometry *before* resolving which way up the
    page is.
    """
    gray = to_gray(img_bgr)
    k = cfg.work_dpi / 25.4
    out_size = (int(round(template.page_w_mm * k)), int(round(template.page_h_mm * k)))
    S = mm_to_px_matrix(cfg.work_dpi)
    blank = np.zeros((out_size[1], out_size[0]), np.uint8)

    warnings: List[str] = []
    method = ""

    # -- coarse homography ------------------------------------------------ #
    H0: Optional[np.ndarray] = None
    if cfg.detect_page:
        quad = find_page_quad(gray, cfg)
        if quad is not None:
            H0 = _page_corner_homography(template, quad)
            method = "page-quad"
    if H0 is None:
        H0 = _identity_frame_homography(template, gray.shape)
        method = "full-frame"

    # -- fiducial refinement ---------------------------------------------- #
    hits = locate_fiducials(gray, template, H0, cfg)
    if len(hits) < 4:
        hunted = hunt_fiducials(gray, template, cfg)
        if len(hunted) == 4:
            hits = hunted
            method += "+hunt"
            # a second local pass from the hunted geometry sharpens the centroids
            refined = locate_fiducials(gray, template, _fiducial_homography(template, hits), cfg)
            if len(refined) == 4:
                hits = refined
    if len(hits) < 4:
        return Alignment(
            ok=False, canonical=blank, raw_canonical=blank, k=k,
            fiducials=hits, method=method,
            errors=[f"corner registration markers not found ({len(hits)}/4) - "
                    f"make sure all four corners of the sheet are inside the frame"],
        )

    if not _sheet_in_frame(hits, gray.shape):
        return Alignment(
            ok=False, canonical=blank, raw_canonical=blank, k=k,
            fiducials=hits, method=method,
            errors=["the sheet is cut off at the edge of the image - "
                    "re-capture with the whole sheet inside the frame"],
        )

    def _warp(h: Dict[str, FiducialHit]) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
        H = _fiducial_homography(template, h)
        M = S @ np.linalg.inv(H)
        raw = cv2.warpPerspective(gray, M, out_size, flags=cv2.INTER_LINEAR,
                                  borderMode=cv2.BORDER_REPLICATE)
        return H, raw, flat_field(raw)

    H, canon_raw, canon = _warp(hits)

    # -- verify the geometry with the timing track ------------------------ #
    rc = RowCorrection()
    if cfg.use_timing_marks:
        rc = measure_timing(canon, template, k, estimate_ink_level(canon), cfg)
        lock = rc.found / max(rc.expected, 1)
        if rc.expected and lock < 0.30:
            return Alignment(
                ok=False, canonical=canon, raw_canonical=canon_raw, k=k, H=H,
                fiducials=hits, method=method,
                errors=[
                    "could not lock onto the sheet's timing marks "
                    f"({rc.found}/{rc.expected} found) - the sheet may be creased, "
                    "cropped, badly lit, or not this template"
                ],
            )

    # -- orientation ------------------------------------------------------ #
    rotated = is_upside_down(canon, template, k)
    if rotated:
        hits = {"tl": hits["br"], "tr": hits["bl"], "br": hits["tl"], "bl": hits["tr"]}
        hits = {n: FiducialHit(n, h.x, h.y, h.area, h.squareness, h.confident)
                for n, h in hits.items()}
        H, canon_raw, canon = _warp(hits)
        if cfg.use_timing_marks:
            rc = measure_timing(canon, template, k, estimate_ink_level(canon), cfg)
        warnings.append("sheet was upside down; corrected automatically")

    return Alignment(
        ok=True,
        canonical=canon,
        raw_canonical=canon_raw,
        k=k,
        H=H,
        fiducials=hits,
        rotated_180=rotated,
        row_correction=rc,
        warnings=warnings,
        method=method,
    )


def skew_degrees(hits: Dict[str, FiducialHit]) -> float:
    """Angle of the top fiducial edge, in degrees -- reported as sheet skew."""
    if "tl" not in hits or "tr" not in hits:
        return 0.0
    dx = hits["tr"].x - hits["tl"].x
    dy = hits["tr"].y - hits["tl"].y
    return float(np.degrees(np.arctan2(dy, dx)))
