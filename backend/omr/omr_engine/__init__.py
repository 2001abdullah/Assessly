"""
omr_engine -- a deterministic OMR (optical mark recognition) engine.

Pure computer vision, no machine learning, no network calls.  The package has no
dependency on the database, the web API or the UI, so it can be lifted into a
CLI, a desktop app, a server, or an Android build without modification.

Typical use::

    from omr_engine import ExamConfig, build_template, OMRProcessor, AnswerKey, score_sheet

    template = build_template(ExamConfig(num_questions=100, num_options=4))
    generate_sheet_pdf(template, "sheet.pdf")        # print this

    proc = OMRProcessor(template)                    # reuse across a batch
    scan = proc.process("student_001.jpg")
    result = score_sheet(scan, answer_key)
"""

from .bubbles import BubbleSamples, Calibration, read_groups, sample_bubbles
from .config import DEFAULT_CONFIG, EngineConfig
from .decode import decode_field
from .detect import Alignment, RowCorrection, align_sheet
from .generator import SheetRenderer, generate_sheet_pdf
from .layout import LayoutError, build_template, solve_question_grid
from .models import (
    AMBIGUOUS_STATUSES,
    BLANK,
    FAINT,
    MARKED,
    MULTI,
    UNREADABLE,
    FieldReading,
    GroupReading,
    QualityReport,
    QuestionOutcome,
    ScoredResult,
    SheetScan,
)
from .pipeline import OMRProcessor, process_image
from .scoring import (
    AMBIGUOUS,
    CORRECT,
    DROPPED,
    NOT_KEYED,
    UNANSWERED,
    WRONG,
    AnswerKey,
    GradeBand,
    ScoringRules,
    score_sheet,
)
from .template import (
    PAGE_SIZES_MM,
    Bubble,
    BubbleGroup,
    ExamConfig,
    Fiducial,
    FieldSpec,
    OMRTemplate,
    TimingTrack,
)

__version__ = "1.0.0"

__all__ = [
    "__version__",
    # template & layout
    "OMRTemplate", "ExamConfig", "Bubble", "BubbleGroup", "Fiducial", "FieldSpec",
    "TimingTrack", "PAGE_SIZES_MM", "build_template", "solve_question_grid", "LayoutError",
    # printing
    "generate_sheet_pdf", "SheetRenderer",
    # engine
    "EngineConfig", "DEFAULT_CONFIG", "OMRProcessor", "process_image",
    "align_sheet", "Alignment", "RowCorrection",
    "sample_bubbles", "read_groups", "BubbleSamples", "Calibration", "decode_field",
    # results
    "SheetScan", "GroupReading", "FieldReading", "QualityReport",
    "ScoredResult", "QuestionOutcome",
    "MARKED", "BLANK", "MULTI", "FAINT", "UNREADABLE", "AMBIGUOUS_STATUSES",
    # scoring
    "AnswerKey", "ScoringRules", "GradeBand", "score_sheet",
    "CORRECT", "WRONG", "UNANSWERED", "AMBIGUOUS", "NOT_KEYED", "DROPPED",
]
