"""
Layout solver: turns an :class:`ExamConfig` into a fully-resolved
:class:`OMRTemplate` with explicit millimetre coordinates for every bubble.

Design notes that matter for scanning accuracy
----------------------------------------------

* **Bubbles are printed empty.**  Option letters are printed once as a column
  header and the digit labels sit in a gutter beside the grid, so nothing is
  ever printed *inside* a bubble.  A glyph inside a bubble contributes a
  baseline dark fraction that varies with the glyph, which is exactly the noise
  the fill decision is trying to measure against.  Keeping bubbles empty gives
  the cleanest possible separation between "marked" and "unmarked".

* **Bubble outlines are light grey and thin.**  The engine samples a disc of
  0.78 x radius, so the printed ring is mostly outside the sampled area, and
  what does leak in is faint.

* **Timing marks line up with question rows.**  After the coarse homography the
  engine looks for these marks and applies a per-row vertical correction, which
  is what absorbs printer scaling and paper stretch.

* **The column count is solved for, not fixed.**  We pick the arrangement that
  maximises the smallest bubble pitch, so a 100-question sheet gets big
  comfortable bubbles and a 200-question sheet still stays inside the minimum
  printable size instead of silently producing something unreadable.
"""

from __future__ import annotations

import math
import uuid
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

from .template import (
    PAGE_SIZES_MM,
    Bubble,
    BubbleGroup,
    ExamConfig,
    Fiducial,
    FieldSpec,
    OMRTemplate,
    TextBox,
    TimingTrack,
)

# --------------------------------------------------------------------------- #
# Fixed geometry (millimetres)
# --------------------------------------------------------------------------- #

FIDUCIAL_INSET_MM = 10.0
FIDUCIAL_SIZE_MM = 6.0
FIDUCIAL_QUIET_MM = 3.0

TIMING_X_INSET_MM = 17.0  # centre of the timing track from the page edge
TIMING_W_MM = 4.0

CONTENT_INSET_MM = 22.0  # left/right content margin from the page edge

MIN_BUBBLE_R_MM = 1.30  # ~2.6 mm across: still ~20 px at 200 dpi
MAX_BUBBLE_R_MM = 2.30
MIN_ROW_PITCH_MM = 3.9
MIN_OPT_PITCH_MM = 4.2

DIGIT_PITCH_X_MM = 6.0
DIGIT_PITCH_Y_MM = 4.6
DIGIT_R_MM = 1.85

QUESTION_LABEL_W_MM = 7.5  # gutter holding the printed question number
COLUMN_GAP_MM = 5.0


class LayoutError(ValueError):
    """Raised when the requested exam cannot be printed reliably on one page."""


@dataclass
class QuestionGrid:
    """Solved arrangement of the question block."""

    columns: int
    rows: int
    col_w_mm: float
    row_pitch_mm: float
    opt_pitch_mm: float
    bubble_r_mm: float


# --------------------------------------------------------------------------- #
# Solver
# --------------------------------------------------------------------------- #


def solve_question_grid(
    num_questions: int,
    num_options: int,
    avail_w_mm: float,
    avail_h_mm: float,
) -> QuestionGrid:
    """
    Choose the column count that gives the largest bubbles while fitting.

    We try every column count and keep the arrangement whose *smallest* pitch is
    largest -- that is the one where bubbles are most comfortably separated in
    both axes, which is what makes the sheet easy to fill and easy to read.
    """
    best: Optional[QuestionGrid] = None
    for columns in range(1, 11):
        rows = math.ceil(num_questions / columns)
        row_pitch = avail_h_mm / rows
        col_w = (avail_w_mm - COLUMN_GAP_MM * (columns - 1)) / columns
        opt_span = col_w - QUESTION_LABEL_W_MM
        if opt_span <= 0:
            continue
        # bubble centres are spread across opt_span with half-pitch padding
        opt_pitch = opt_span / num_options
        if row_pitch < MIN_ROW_PITCH_MM or opt_pitch < MIN_OPT_PITCH_MM:
            continue
        r = min(row_pitch, opt_pitch) * 0.34
        r = max(MIN_BUBBLE_R_MM, min(MAX_BUBBLE_R_MM, r))
        cand = QuestionGrid(columns, rows, col_w, row_pitch, opt_pitch, r)
        score = min(row_pitch, opt_pitch)
        if best is None or score > min(best.row_pitch_mm, best.opt_pitch_mm):
            best = cand
    if best is None:
        raise LayoutError(
            f"{num_questions} questions x {num_options} options do not fit on this "
            f"page at a printable bubble size. Use a larger page (A3), reduce the "
            f"question count, or reduce the number of options."
        )
    return best


# --------------------------------------------------------------------------- #
# Template construction
# --------------------------------------------------------------------------- #


def build_template(
    config: ExamConfig,
    template_id: Optional[str] = None,
    name: Optional[str] = None,
) -> OMRTemplate:
    """Resolve ``config`` into a complete, validated :class:`OMRTemplate`."""

    page_key = config.page_size.upper()
    if page_key not in PAGE_SIZES_MM:
        raise LayoutError(
            f"unknown page size {config.page_size!r}; known: {sorted(PAGE_SIZES_MM)}"
        )
    W, H = PAGE_SIZES_MM[page_key]

    if config.num_options < 2 or config.num_options > 6:
        raise LayoutError("num_options must be between 2 and 6")
    if config.num_questions < 1:
        raise LayoutError("num_questions must be at least 1")
    if not (1 <= config.roll_digits <= 14):
        raise LayoutError("roll_digits must be between 1 and 14")
    if not (0 <= config.registration_digits <= 16):
        raise LayoutError("registration_digits must be between 0 and 16")

    labels = config.resolved_labels()
    tid = template_id or f"tpl_{uuid.uuid4().hex[:12]}"

    # --- fiducials & region of interest -------------------------------- #
    fi = FIDUCIAL_INSET_MM
    fiducials = [
        Fiducial("tl", fi, fi, FIDUCIAL_SIZE_MM, FIDUCIAL_QUIET_MM),
        Fiducial("tr", W - fi, fi, FIDUCIAL_SIZE_MM, FIDUCIAL_QUIET_MM),
        Fiducial("bl", fi, H - fi, FIDUCIAL_SIZE_MM, FIDUCIAL_QUIET_MM),
        Fiducial("br", W - fi, H - fi, FIDUCIAL_SIZE_MM, FIDUCIAL_QUIET_MM),
    ]
    roi = (fi, fi, W - fi, H - fi)

    content_x0 = CONTENT_INSET_MM
    content_x1 = W - CONTENT_INSET_MM
    content_w = content_x1 - content_x0

    texts: List[TextBox] = []
    groups: List[BubbleGroup] = []
    fields: Dict[str, FieldSpec] = {}

    # --- header text ---------------------------------------------------- #
    texts.append(
        TextBox(content_x0, 13.0, content_w, 6.0, config.exam_name, font_size=13.0, bold=True)
    )
    meta_bits = [b for b in (config.subject, config.exam_code) if b]
    meta_line = "   |   ".join(meta_bits)
    if meta_line:
        texts.append(TextBox(content_x0, 19.0, content_w, 4.0, meta_line, font_size=8.5))
    texts.append(
        TextBox(
            content_x0,
            24.0,
            content_w,
            7.0,
            config.instructions,
            font_size=6.2,
            box=False,
        )
    )
    scoring_line = (
        f"Correct +{_fmt(config.marks_correct)}   "
        f"Wrong {_fmt(config.marks_wrong, signed=True)}   "
        f"Unanswered {_fmt(config.marks_blank, signed=True)}   "
        f"Questions {config.num_questions}"
    )
    texts.append(TextBox(content_x0, 30.0, content_w, 4.0, scoring_line, font_size=6.2))

    # --- identification block ------------------------------------------ #
    id_top = 35.0
    grid_label_h = 4.0
    handwrite_h = 7.0
    grid_first_y = id_top + grid_label_h + handwrite_h + 3.0
    grid_bottom = grid_first_y + 9 * DIGIT_PITCH_Y_MM + DIGIT_R_MM

    cursor_x = content_x0
    for fname, title, digits in (
        ("roll", "ROLL NUMBER", config.roll_digits),
        ("registration", "REGISTRATION NUMBER", config.registration_digits),
    ):
        if digits <= 0:
            continue
        block_w = digits * DIGIT_PITCH_X_MM
        if cursor_x + block_w > content_x1:
            raise LayoutError(
                "roll + registration digit columns are too wide for this page; "
                "reduce the digit counts or use a larger page"
            )
        texts.append(
            TextBox(cursor_x, id_top, block_w, grid_label_h, title, font_size=6.8, bold=True)
        )
        # handwriting boxes, one per digit, above the grid
        for d in range(digits):
            texts.append(
                TextBox(
                    cursor_x + d * DIGIT_PITCH_X_MM + 0.4,
                    id_top + grid_label_h,
                    DIGIT_PITCH_X_MM - 0.8,
                    handwrite_h,
                    "",
                    box=True,
                )
            )
        keys: List[str] = []
        for d in range(digits):
            cx = cursor_x + d * DIGIT_PITCH_X_MM + DIGIT_PITCH_X_MM / 2.0
            bubbles = [
                Bubble(cx, grid_first_y + v * DIGIT_PITCH_Y_MM, DIGIT_R_MM, str(v), str(v))
                for v in range(10)
            ]
            key = f"{fname}.d{d}"
            groups.append(BubbleGroup(key, "digit", d, bubbles, owner=fname))
            keys.append(key)
        fields[fname] = FieldSpec(fname, title, digits, keys)

        # 0-9 gutter labels to the left of the first column
        for v in range(10):
            texts.append(
                TextBox(
                    cursor_x - 4.2,
                    grid_first_y + v * DIGIT_PITCH_Y_MM - 1.6,
                    3.4,
                    3.2,
                    str(v),
                    font_size=5.6,
                    align="right",
                )
            )
        cursor_x += block_w + 10.0

    # name / signature box occupying whatever is left to the right
    if config.include_name_box and content_x1 - cursor_x > 30.0:
        texts.append(
            TextBox(cursor_x, id_top, content_x1 - cursor_x, grid_label_h,
                    "CANDIDATE NAME", font_size=6.8, bold=True)
        )
        texts.append(
            TextBox(cursor_x, id_top + grid_label_h, content_x1 - cursor_x,
                    handwrite_h + 6.0, "", box=True)
        )
        texts.append(
            TextBox(cursor_x, id_top + grid_label_h + handwrite_h + 9.0,
                    content_x1 - cursor_x, grid_label_h, "SIGNATURE", font_size=6.8, bold=True)
        )
        texts.append(
            TextBox(cursor_x, id_top + grid_label_h * 2 + handwrite_h + 9.0,
                    content_x1 - cursor_x, handwrite_h + 4.0, "", box=True)
        )

    # --- question block -------------------------------------------------- #
    q_top = max(grid_bottom + 6.0, 95.0)
    q_header_h = 3.6
    q_bottom = H - FIDUCIAL_INSET_MM - FIDUCIAL_SIZE_MM / 2 - 4.0
    avail_h = q_bottom - (q_top + q_header_h)
    if avail_h < 20:
        raise LayoutError("no vertical room left for the question block")

    grid = solve_question_grid(config.num_questions, config.num_options, content_w, avail_h)

    row_pitch = grid.row_pitch_mm
    first_row_y = q_top + q_header_h + row_pitch / 2.0

    qno = 1
    for c in range(grid.columns):
        col_x0 = content_x0 + c * (grid.col_w_mm + COLUMN_GAP_MM)
        opt_x0 = col_x0 + QUESTION_LABEL_W_MM
        # option letter header for this column
        for oi, lab in enumerate(labels):
            ox = opt_x0 + (oi + 0.5) * grid.opt_pitch_mm
            texts.append(
                TextBox(ox - 2.0, q_top, 4.0, q_header_h, lab, font_size=6.4,
                        bold=True, align="center")
            )
        for r in range(grid.rows):
            if qno > config.num_questions:
                break
            cy = first_row_y + r * row_pitch
            texts.append(
                TextBox(col_x0, cy - 1.7, QUESTION_LABEL_W_MM - 1.4, 3.4, str(qno),
                        font_size=6.2, align="right")
            )
            bubbles = [
                Bubble(opt_x0 + (oi + 0.5) * grid.opt_pitch_mm, cy,
                       grid.bubble_r_mm, lab, lab)
                for oi, lab in enumerate(labels)
            ]
            groups.append(BubbleGroup(f"q{qno}", "question", qno, bubbles, owner="questions"))
            qno += 1

    # --- timing marks --------------------------------------------------- #
    row_ys = [first_row_y + r * row_pitch for r in range(grid.rows)]
    mark_h = max(1.6, min(2.6, row_pitch * 0.42))
    timing_tracks = [
        TimingTrack("left", TIMING_X_INSET_MM, TIMING_W_MM, mark_h, list(row_ys)),
        TimingTrack("right", W - TIMING_X_INSET_MM, TIMING_W_MM, mark_h, list(row_ys)),
    ]

    # --- QR identifier --------------------------------------------------- #
    qr_size = 14.0
    qr_x = content_x1 - qr_size
    qr_y = 12.0
    qr_payload = "|".join(
        [
            "OMR1",
            tid,
            str(config.num_questions),
            str(config.num_options),
            str(config.roll_digits),
            str(config.registration_digits),
        ]
    )
    # keep the header title clear of the QR block
    texts[0] = TextBox(content_x0, 13.0, content_w - qr_size - 4.0, 6.0,
                       config.exam_name, font_size=13.0, bold=True)

    tpl = OMRTemplate(
        template_id=tid,
        name=name or config.exam_name,
        page_w_mm=W,
        page_h_mm=H,
        config=config,
        fiducials=fiducials,
        timing_tracks=timing_tracks,
        groups=groups,
        fields=fields,
        texts=texts,
        bubble_r_mm=grid.bubble_r_mm,
        qr_x_mm=qr_x,
        qr_y_mm=qr_y,
        qr_size_mm=qr_size,
        qr_payload=qr_payload,
        roi=roi,
        meta={
            "columns": grid.columns,
            "rows": grid.rows,
            "row_pitch_mm": round(row_pitch, 3),
            "opt_pitch_mm": round(grid.opt_pitch_mm, 3),
            "question_top_mm": round(q_top, 2),
            "question_bottom_mm": round(q_bottom, 2),
        },
    )

    problems = tpl.validate()
    if problems:
        raise LayoutError("generated template failed validation: " + "; ".join(problems[:6]))
    return tpl


def _fmt(v: float, signed: bool = False) -> str:
    s = f"{v:g}"
    if signed and v > 0:
        s = "+" + s
    return s
