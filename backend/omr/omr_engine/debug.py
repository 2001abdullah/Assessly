"""
Debug overlay renderer.

Draws what the engine decided directly on the canonical page: green for a
confident mark, amber for faint, red for a multi-mark, thin grey for empty.  A
human can verify a whole batch by flipping through these, which is the fastest
way to trust or distrust a threshold change.
"""

from __future__ import annotations

from typing import Dict, Optional

import cv2
import numpy as np

from .bubbles import BubbleSamples
from .detect import RowCorrection
from .models import BLANK, FAINT, MARKED, MULTI, GroupReading
from .template import OMRTemplate

COLOURS = {
    MARKED: (60, 190, 70),
    FAINT: (40, 175, 245),
    MULTI: (60, 60, 235),
    BLANK: (185, 185, 185),
}


def render_overlay(
    canon: np.ndarray,
    template: OMRTemplate,
    samples: BubbleSamples,
    readings: Dict[str, GroupReading],
    rc: RowCorrection,
    k: float,
    out_path: Optional[str] = None,
) -> np.ndarray:
    vis = cv2.cvtColor(canon, cv2.COLOR_GRAY2BGR)

    # fiducial and timing reference marks
    for f in template.fiducials:
        c = (int(f.x_mm * k), int(f.y_mm * k))
        cv2.drawMarker(vis, c, (255, 120, 0), cv2.MARKER_CROSS, int(6 * k), 2)

    for track in template.timing_tracks:
        for y in track.y_positions_mm:
            x0 = int((track.x_mm - track.w_mm / 2) * k)
            y0 = int((y - track.h_mm / 2) * k)
            x1 = int((track.x_mm + track.w_mm / 2) * k)
            y1 = int((y + track.h_mm / 2) * k)
            cv2.rectangle(vis, (x0, y0), (x1, y1), (255, 160, 60), 1)

    thr = samples.calibration.fill_threshold
    for g in template.groups:
        r = readings.get(g.key)
        if r is None:
            continue
        centres = samples.centres.get(g.key)
        radii = samples.radii.get(g.key)
        if centres is None or radii is None:
            continue
        scores = samples.scores.get(g.key, np.zeros(len(g.bubbles)))
        for i, b in enumerate(g.bubbles):
            cx, cy = int(centres[i][0]), int(centres[i][1])
            rad = int(radii[i])
            filled = scores[i] >= thr
            if r.status == MARKED and b.value == r.value:
                colour, th = COLOURS[MARKED], 2
            elif r.status == MULTI and filled:
                colour, th = COLOURS[MULTI], 2
            elif r.status == FAINT and scores[i] == scores.max():
                colour, th = COLOURS[FAINT], 2
            else:
                colour, th = COLOURS[BLANK], 1
            cv2.circle(vis, (cx, cy), rad, colour, th)

    banner = (
        f"ink={samples.calibration.ink_threshold:.0f}"
        f"  fill={thr:.2f}"
        f"{' (calibrated)' if samples.calibration.fill_calibrated else ' (default)'}"
        f"  timing={rc.found}/{rc.expected}"
        f"  rms={rc.rms_px:.2f}px"
    )
    cv2.rectangle(vis, (0, 0), (vis.shape[1], int(9 * k)), (255, 255, 255), -1)
    cv2.putText(vis, banner, (int(3 * k), int(6.2 * k)), cv2.FONT_HERSHEY_SIMPLEX,
                0.45 * k / 7.87, (25, 25, 25), 1, cv2.LINE_AA)

    if out_path:
        cv2.imwrite(out_path, vis)
    return vis
