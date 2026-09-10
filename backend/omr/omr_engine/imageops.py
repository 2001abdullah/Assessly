"""Low-level image utilities shared by the detection and sampling stages."""

from __future__ import annotations

from typing import Optional, Tuple, Union

import cv2
import numpy as np

ArrayLike = Union[str, bytes, bytearray, np.ndarray]


# --------------------------------------------------------------------------- #
# Loading
# --------------------------------------------------------------------------- #


def load_image(src: ArrayLike, max_pixels: int = 40_000_000) -> np.ndarray:
    """Load ``src`` (path, encoded bytes or array) as a BGR uint8 image."""
    if isinstance(src, np.ndarray):
        img = src
    elif isinstance(src, (bytes, bytearray)):
        buf = np.frombuffer(bytes(src), dtype=np.uint8)
        img = cv2.imdecode(buf, cv2.IMREAD_COLOR)
        if img is None:
            raise ValueError("could not decode image bytes")
    else:
        img = cv2.imread(str(src), cv2.IMREAD_COLOR)
        if img is None:
            raise ValueError(f"could not read image: {src}")

    if img.ndim == 2:
        img = cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)
    elif img.shape[2] == 4:
        img = cv2.cvtColor(img, cv2.COLOR_BGRA2BGR)

    h, w = img.shape[:2]
    if h * w > max_pixels:
        scale = (max_pixels / float(h * w)) ** 0.5
        img = cv2.resize(img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)
    return img


def to_gray(img: np.ndarray) -> np.ndarray:
    if img.ndim == 2:
        return img
    return cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)


# --------------------------------------------------------------------------- #
# Illumination
# --------------------------------------------------------------------------- #


def flat_field(gray: np.ndarray, scale: int = 8, close_ksize: int = 11) -> np.ndarray:
    """
    Remove shadows and vignetting by dividing out an estimated background.

    The background is estimated on a heavily downscaled copy with a
    morphological *closing*, which erases dark structures (text, bubbles, pencil
    marks) while keeping the slow illumination gradient.  Dividing the original
    by that background leaves the paper at a uniform level, so a single ink cut
    works across a shadowed page.

    Returns a uint8 image where clean paper sits near 255.
    """
    h, w = gray.shape[:2]
    sw, sh = max(8, w // scale), max(8, h // scale)
    small = cv2.resize(gray, (sw, sh), interpolation=cv2.INTER_AREA)
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (close_ksize, close_ksize))
    bg_small = cv2.morphologyEx(small, cv2.MORPH_CLOSE, k)
    bg_small = cv2.GaussianBlur(bg_small, (0, 0), 3.0)
    bg = cv2.resize(bg_small, (w, h), interpolation=cv2.INTER_LINEAR).astype(np.float32)
    bg = np.maximum(bg, 12.0)
    norm = (gray.astype(np.float32) / bg) * 235.0
    return np.clip(norm, 0, 255).astype(np.uint8)


# --------------------------------------------------------------------------- #
# Quality metrics
# --------------------------------------------------------------------------- #


def sharpness(gray: np.ndarray) -> float:
    """Variance of the Laplacian -- the standard blur proxy."""
    if gray.size == 0:
        return 0.0
    small = gray
    if max(gray.shape) > 1400:
        s = 1400.0 / max(gray.shape)
        small = cv2.resize(gray, None, fx=s, fy=s, interpolation=cv2.INTER_AREA)
    return float(cv2.Laplacian(small, cv2.CV_64F).var())


def contrast(gray: np.ndarray) -> float:
    """Robust dynamic range in 0..1, ignoring the extreme tails."""
    if gray.size == 0:
        return 0.0
    lo, hi = np.percentile(gray, (2.0, 98.0))
    return float(max(0.0, (hi - lo) / 255.0))


# --------------------------------------------------------------------------- #
# Geometry helpers
# --------------------------------------------------------------------------- #


def order_quad(pts: np.ndarray) -> np.ndarray:
    """Order 4 points as top-left, top-right, bottom-right, bottom-left."""
    pts = np.asarray(pts, dtype=np.float32).reshape(4, 2)
    s = pts.sum(axis=1)
    d = np.diff(pts, axis=1).ravel()
    return np.array(
        [pts[np.argmin(s)], pts[np.argmin(d)], pts[np.argmax(s)], pts[np.argmax(d)]],
        dtype=np.float32,
    )


def mm_to_px_matrix(dpi: int) -> np.ndarray:
    """Scale matrix mapping page millimetres to canonical pixels."""
    k = dpi / 25.4
    return np.array([[k, 0.0, 0.0], [0.0, k, 0.0], [0.0, 0.0, 1.0]], dtype=np.float64)


def apply_h(H: np.ndarray, pts: np.ndarray) -> np.ndarray:
    """Apply a 3x3 homography to an (N,2) array of points."""
    pts = np.asarray(pts, dtype=np.float64).reshape(-1, 1, 2)
    out = cv2.perspectiveTransform(pts, H.astype(np.float64))
    return out.reshape(-1, 2)


def homography_scale(H: np.ndarray) -> float:
    """Approximate uniform pixels-per-input-unit implied by ``H`` at its centre."""
    p = apply_h(H, np.array([[0.0, 0.0], [1.0, 0.0], [0.0, 1.0]]))
    a = np.linalg.norm(p[1] - p[0])
    b = np.linalg.norm(p[2] - p[0])
    return float((a + b) / 2.0)


def binarize_inverse(gray: np.ndarray, block: int = 41, C: int = 12) -> np.ndarray:
    """Adaptive inverse threshold: ink becomes white (255), paper black."""
    block = max(3, block | 1)
    return cv2.adaptiveThreshold(
        gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY_INV, block, C
    )


def otsu_threshold(values: np.ndarray) -> Tuple[float, float]:
    """
    Otsu split of a 1-D sample, returned as ``(threshold, separability)``.

    ``separability`` is the between-class variance over the total variance in
    0..1; near 1 means a clean bimodal split, near 0 means one blob and the
    threshold should not be trusted.
    """
    v = np.asarray(values, dtype=np.float64).ravel()
    v = v[np.isfinite(v)]
    if v.size < 8:
        return (float("nan"), 0.0)
    lo, hi = float(v.min()), float(v.max())
    if hi - lo < 1e-6:
        return (float("nan"), 0.0)
    q = ((v - lo) / (hi - lo) * 255.0).astype(np.uint8)
    t8, _ = cv2.threshold(q, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    thr = lo + (float(t8) / 255.0) * (hi - lo)
    a, b = v[v <= thr], v[v > thr]
    total = v.var()
    if a.size == 0 or b.size == 0 or total <= 1e-12:
        return (thr, 0.0)
    wa, wb = a.size / v.size, b.size / v.size
    between = wa * wb * (a.mean() - b.mean()) ** 2
    return (thr, float(np.clip(between / total, 0.0, 1.0)))


def disc_offsets(radius: float) -> Tuple[np.ndarray, np.ndarray]:
    """Integer (dy, dx) offsets covering a filled disc of ``radius`` pixels."""
    r = max(1, int(round(radius)))
    ys, xs = np.mgrid[-r : r + 1, -r : r + 1]
    mask = (ys * ys + xs * xs) <= (radius * radius)
    return ys[mask].astype(np.int32), xs[mask].astype(np.int32)


def largest_dark_blob_centroid(
    window: np.ndarray, ink_thresh: int, min_area: int = 6
) -> Optional[Tuple[float, float, float]]:
    """
    Centroid of the largest dark blob in ``window``.

    Returns ``(cx, cy, area)`` in window coordinates, or None.
    """
    _, bw = cv2.threshold(window, ink_thresh, 255, cv2.THRESH_BINARY_INV)
    n, labels, stats, cents = cv2.connectedComponentsWithStats(bw, connectivity=8)
    best_i, best_area = -1, 0
    for i in range(1, n):
        area = int(stats[i, cv2.CC_STAT_AREA])
        if area >= min_area and area > best_area:
            best_area, best_i = area, i
    if best_i < 0:
        return None
    cx, cy = cents[best_i]
    return (float(cx), float(cy), float(best_area))
