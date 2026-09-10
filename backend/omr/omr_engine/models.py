"""Result objects produced by the OMR engine.

These are plain dataclasses with no OpenCV, database or web dependencies, so
they serialise cleanly to JSON and can cross a process boundary in the batch
worker.
"""

from __future__ import annotations

from dataclasses import dataclass, field, asdict
from typing import Any, Dict, List, Optional


# --------------------------------------------------------------------------- #
# Status vocabulary
# --------------------------------------------------------------------------- #

MARKED = "marked"
BLANK = "blank"
MULTI = "multi"  # more than one bubble filled
FAINT = "faint"  # something is there, but below the confident-mark threshold
UNREADABLE = "unreadable"  # geometry or quality failure

AMBIGUOUS_STATUSES = {MULTI, FAINT, UNREADABLE}


# --------------------------------------------------------------------------- #
# Readings
# --------------------------------------------------------------------------- #


@dataclass
class GroupReading:
    """The engine's decision for one mutually-exclusive bubble group."""

    key: str
    kind: str  # "question" | "digit"
    index: int
    owner: str
    value: Optional[str]
    status: str
    confidence: float
    scores: List[float] = field(default_factory=list)
    labels: List[str] = field(default_factory=list)

    @property
    def is_ambiguous(self) -> bool:
        return self.status in AMBIGUOUS_STATUSES

    def top_two(self) -> tuple:
        if not self.scores:
            return (0.0, 0.0)
        s = sorted(self.scores, reverse=True)
        return (s[0], s[1] if len(s) > 1 else 0.0)

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        d["scores"] = [round(float(s), 4) for s in self.scores]
        d["confidence"] = round(float(self.confidence), 4)
        return d


@dataclass
class FieldReading:
    """A multi-digit field such as roll or registration number."""

    name: str
    value: Optional[str]
    digits: List[Optional[str]] = field(default_factory=list)
    statuses: List[str] = field(default_factory=list)
    confidence: float = 0.0
    needs_review: bool = False
    note: str = ""

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        d["confidence"] = round(float(self.confidence), 4)
        return d


@dataclass
class QualityReport:
    """Measured image quality and geometry health for one scanned sheet."""

    sharpness: float = 0.0
    contrast: float = 0.0
    reprojection_error_px: float = 0.0
    fiducials_found: int = 0
    timing_marks_found: int = 0
    timing_marks_expected: int = 0
    ink_threshold: float = 0.0
    fill_threshold: float = 0.0
    skew_deg: float = 0.0
    grade: str = "unknown"  # excellent | good | fair | poor
    score: float = 0.0  # 0..1

    def to_dict(self) -> Dict[str, Any]:
        return {k: (round(v, 4) if isinstance(v, float) else v)
                for k, v in asdict(self).items()}


@dataclass
class SheetScan:
    """Everything the engine extracted from one image."""

    ok: bool
    template_id: str = ""
    source: str = ""
    roll: Optional[FieldReading] = None
    registration: Optional[FieldReading] = None
    answers: List[GroupReading] = field(default_factory=list)
    quality: QualityReport = field(default_factory=QualityReport)
    warnings: List[str] = field(default_factory=list)
    errors: List[str] = field(default_factory=list)
    qr_payload: str = ""
    elapsed_ms: float = 0.0
    needs_review: bool = False
    debug_image_path: str = ""

    # -- convenience -------------------------------------------------- #
    @property
    def answer_map(self) -> Dict[int, Optional[str]]:
        return {a.index: a.value for a in self.answers}

    def ambiguous_questions(self) -> List[int]:
        return [a.index for a in self.answers if a.is_ambiguous]

    def counts(self) -> Dict[str, int]:
        out = {MARKED: 0, BLANK: 0, MULTI: 0, FAINT: 0, UNREADABLE: 0}
        for a in self.answers:
            out[a.status] = out.get(a.status, 0) + 1
        return out

    def to_dict(self) -> Dict[str, Any]:
        return {
            "ok": self.ok,
            "template_id": self.template_id,
            "source": self.source,
            "roll": self.roll.to_dict() if self.roll else None,
            "registration": self.registration.to_dict() if self.registration else None,
            "answers": [a.to_dict() for a in self.answers],
            "quality": self.quality.to_dict(),
            "warnings": self.warnings,
            "errors": self.errors,
            "qr_payload": self.qr_payload,
            "elapsed_ms": round(self.elapsed_ms, 2),
            "needs_review": self.needs_review,
            "debug_image_path": self.debug_image_path,
        }


# --------------------------------------------------------------------------- #
# Scoring
# --------------------------------------------------------------------------- #


@dataclass
class QuestionOutcome:
    number: int
    given: Optional[str]
    expected: Optional[str]
    status: str  # correct | wrong | blank | ambiguous | not_keyed
    marks: float

    def to_dict(self) -> Dict[str, Any]:
        return {"number": self.number, "given": self.given, "expected": self.expected,
                "status": self.status, "marks": round(self.marks, 4)}


@dataclass
class ScoredResult:
    roll: Optional[str]
    registration: Optional[str]
    name: str = ""
    correct: int = 0
    wrong: int = 0
    blank: int = 0
    ambiguous: int = 0
    total_questions: int = 0
    marks: float = 0.0
    max_marks: float = 0.0
    percentage: float = 0.0
    grade: str = ""
    passed: bool = False
    outcomes: List[QuestionOutcome] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "roll": self.roll,
            "registration": self.registration,
            "name": self.name,
            "correct": self.correct,
            "wrong": self.wrong,
            "blank": self.blank,
            "ambiguous": self.ambiguous,
            "total_questions": self.total_questions,
            "marks": round(self.marks, 4),
            "max_marks": round(self.max_marks, 4),
            "percentage": round(self.percentage, 2),
            "grade": self.grade,
            "passed": self.passed,
            "outcomes": [o.to_dict() for o in self.outcomes],
        }
