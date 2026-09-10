"""Answer keys, scoring rules and result calculation."""

from __future__ import annotations

import csv
import io
import json
import re
from dataclasses import dataclass, field, asdict
from typing import Any, Dict, List, Optional, Sequence

from .models import (
    AMBIGUOUS_STATUSES,
    BLANK,
    QuestionOutcome,
    ScoredResult,
    SheetScan,
)


# Question outcome vocabulary

CORRECT = "correct"
WRONG = "wrong"
UNANSWERED = "blank"
AMBIGUOUS = "ambiguous"
NOT_KEYED = "not_keyed"
DROPPED = "dropped"


@dataclass
class GradeBand:
    label: str
    min_percent: float

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


# Default grade bands.
# These are defaults only and can be changed through scoring rules.

DEFAULT_GRADE_BANDS = [
    GradeBand("A+", 80.0),
    GradeBand("A", 70.0),
    GradeBand("A-", 60.0),
    GradeBand("B", 50.0),
    GradeBand("C", 40.0),
    GradeBand("D", 33.0),
    GradeBand("F", 0.0),
]


@dataclass
class ScoringRules:
    """
    Scoring rules for the entire exam.

    The same values are applied to every question.

    Example:

        marks_correct = 1
        marks_wrong   = -0.5
        marks_blank   = 0

    means:

        Correct → +1
        Wrong   → -0.5
        Blank   → 0
    """

    marks_correct: float = 1.0
    marks_wrong: float = 0.0
    marks_blank: float = 0.0

    pass_percentage: float = 33.0

    grade_bands: List[GradeBand] = field(
        default_factory=lambda: list(DEFAULT_GRADE_BANDS)
    )

    ambiguous_as: str = "review"
    """
    How an ambiguous answer scores when a result is produced anyway.

    "review" → 0 marks and the sheet is flagged
    "wrong"  → use marks_wrong
    "blank"  → use marks_blank
    """

    clamp_negative_total: bool = True
    """Never report a negative total; floor the sheet at zero."""

    @property
    def has_negative_marking(self) -> bool:
        return self.marks_wrong < 0

    def grade_for(self, percentage: float) -> str:
        for band in sorted(
            self.grade_bands,
            key=lambda b: b.min_percent,
            reverse=True,
        ):
            if percentage >= band.min_percent:
                return band.label

        return ""

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)

        d["grade_bands"] = [
            band.to_dict()
            for band in self.grade_bands
        ]

        return d

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "ScoringRules":
        d = dict(d or {})

        bands = d.pop("grade_bands", None)

        known = {
            f
            for f in cls.__dataclass_fields__
        }

        obj = cls(
            **{
                k: v
                for k, v in d.items()
                if k in known
            }
        )

        if bands:
            obj.grade_bands = [
                GradeBand(
                    b["label"],
                    float(b["min_percent"]),
                )
                for b in bands
            ]

        return obj


@dataclass
class AnswerKey:
    """
    The correct answers for one exam.

    ``answers`` maps a 1-based question number to one of:

    * ``"A"``              -- a single correct option
    * ``"AC"`` / ``"A,C"`` -- any of several options accepted
    * ``"*"``              -- question dropped; every candidate gets the marks
    * ``None``             -- not keyed; excluded from the total
    """

    key_id: str = ""
    name: str = "Answer Key"
    total_questions: int = 0

    answers: Dict[int, Optional[str]] = field(
        default_factory=dict
    )

    rules: ScoringRules = field(
        default_factory=ScoringRules
    )

    # ------------------------------------------------------------------ #
    # Construction
    # ------------------------------------------------------------------ #

    @classmethod
    def from_sequence(
        cls,
        seq: Sequence[Optional[str]],
        **kw: Any,
    ) -> "AnswerKey":

        answers = {
            i + 1: _norm(v)
            for i, v in enumerate(seq)
        }

        return cls(
            total_questions=len(seq),
            answers=answers,
            **kw,
        )

    @classmethod
    def from_text(
        cls,
        text: str,
        **kw: Any,
    ) -> "AnswerKey":

        """
        Parse a free-form answer key.

        Accepts:

            1 A
            1. A
            1: A
            1,A

        per line, or a bare run of letters like:

            ABCDACBD...
        """

        answers: Dict[int, Optional[str]] = {}

        pair_re = re.compile(
            r"^\s*(\d+)\s*[.):,\-\t ]\s*([A-Za-z*,\s]+?)\s*$"
        )

        loose: List[str] = []

        for raw in text.splitlines():

            line = raw.strip()

            if not line or line.startswith("#"):
                continue

            match = pair_re.match(line)

            if match:
                answers[
                    int(match.group(1))
                ] = _norm(match.group(2))

            else:
                loose.extend(
                    re.findall(
                        r"[A-Za-z*]",
                        line,
                    )
                )

        if not answers and loose:

            answers = {
                i + 1: _norm(v)
                for i, v in enumerate(loose)
            }

        total = max(answers) if answers else 0

        return cls(
            total_questions=total,
            answers=answers,
            **kw,
        )

    @classmethod
    def from_csv(
        cls,
        text: str,
        **kw: Any,
    ) -> "AnswerKey":

        """
        Parse:

            question,answer

        CSV.

        Marking values are NOT stored per question.
        They belong to ScoringRules for the entire exam.
        """

        answers: Dict[int, Optional[str]] = {}

        reader = csv.reader(
            io.StringIO(text)
        )

        for row in reader:

            if not row or not row[0].strip():
                continue

            head = row[0].strip().lower()

            if head in {
                "question",
                "q",
                "qno",
                "no",
                "sl",
            }:
                continue

            try:
                q = int(
                    re.sub(
                        r"\D",
                        "",
                        row[0],
                    )
                )

            except ValueError:
                continue

            ans = (
                _norm(row[1])
                if len(row) > 1
                else None
            )

            answers[q] = ans

        return cls(
            total_questions=max(answers)
            if answers
            else 0,
            answers=answers,
            **kw,
        )

    # ------------------------------------------------------------------ #
    # Validation
    # ------------------------------------------------------------------ #

    def validate(
        self,
        num_questions: int,
        option_labels: Sequence[str],
    ) -> List[str]:

        problems: List[str] = []

        valid = {
            o.upper()
            for o in option_labels
        }

        for q in range(
            1,
            num_questions + 1,
        ):

            if q not in self.answers:
                problems.append(
                    f"question {q} has no key entry"
                )

        for q, answer in self.answers.items():

            if q < 1 or q > num_questions:

                problems.append(
                    f"key has question {q}, "
                    f"outside 1..{num_questions}"
                )

            if answer in (
                None,
                "*",
            ):
                continue

            for ch in answer:

                if ch not in valid:

                    problems.append(
                        f"question {q}: "
                        f"option {ch!r} is not one of "
                        f"{sorted(valid)}"
                    )

        return problems

    def missing_questions(
        self,
        num_questions: int,
    ) -> List[int]:

        return [
            q
            for q in range(
                1,
                num_questions + 1,
            )
            if self.answers.get(q) is None
        ]

    # ------------------------------------------------------------------ #
    # Serialization
    # ------------------------------------------------------------------ #

    def to_dict(self) -> Dict[str, Any]:

        return {
            "key_id": self.key_id,
            "name": self.name,
            "total_questions": self.total_questions,
            "answers": {
                str(k): v
                for k, v in sorted(
                    self.answers.items()
                )
            },
            "rules": self.rules.to_dict(),
        }

    @classmethod
    def from_dict(
        cls,
        d: Dict[str, Any],
    ) -> "AnswerKey":

        return cls(
            key_id=d.get(
                "key_id",
                "",
            ),

            name=d.get(
                "name",
                "Answer Key",
            ),

            total_questions=int(
                d.get(
                    "total_questions",
                    0,
                )
            ),

            answers={
                int(k): v
                for k, v in (
                    d.get("answers") or {}
                ).items()
            },

            rules=ScoringRules.from_dict(
                d.get(
                    "rules",
                    {},
                )
            ),
        )

    def to_json(self) -> str:

        return json.dumps(
            self.to_dict(),
            indent=2,
        )

    @classmethod
    def from_json(
        cls,
        text: str,
    ) -> "AnswerKey":

        return cls.from_dict(
            json.loads(text)
        )


def _norm(
    v: Optional[str],
) -> Optional[str]:

    if v is None:
        return None

    s = re.sub(
        r"[^A-Za-z*]",
        "",
        str(v),
    ).upper()

    if not s:
        return None

    if "*" in s:
        return "*"

    return "".join(
        sorted(set(s))
    )


# --------------------------------------------------------------------------- #
# Scoring
# --------------------------------------------------------------------------- #


def score_sheet(
    scan: SheetScan,
    key: AnswerKey,
    num_questions: Optional[int] = None,
    name: str = "",
) -> ScoredResult:

    """
    Compare a SheetScan against an AnswerKey.

    The same exam-wide scoring rules are applied to every question.
    """

    rules = key.rules

    total_q = (
        num_questions
        or key.total_questions
        or len(scan.answers)
    )

    by_index = {
        a.index: a
        for a in scan.answers
    }

    outcomes: List[QuestionOutcome] = []

    correct = 0
    wrong = 0
    blank = 0
    ambiguous = 0

    marks = 0.0
    max_marks = 0.0

    for q in range(
        1,
        total_q + 1,
    ):

        expected = key.answers.get(q)

        reading = by_index.get(q)

        given = (
            reading.value
            if reading
            else None
        )

        status_in = (
            reading.status
            if reading
            else BLANK
        )

        # -------------------------------------------------------------- #
        # Every question uses the same marks_correct value.
        # -------------------------------------------------------------- #

        q_marks = rules.marks_correct

        # -------------------------------------------------------------- #
        # Question not included in answer key.
        # -------------------------------------------------------------- #

        if expected is None:

            outcomes.append(
                QuestionOutcome(
                    q,
                    given,
                    None,
                    NOT_KEYED,
                    0.0,
                )
            )

            continue

        max_marks += q_marks

        # -------------------------------------------------------------- #
        # Dropped question.
        # Everyone receives full marks.
        # -------------------------------------------------------------- #

        if expected == "*":

            marks += q_marks
            correct += 1

            outcomes.append(
                QuestionOutcome(
                    q,
                    given,
                    "*",
                    DROPPED,
                    q_marks,
                )
            )

            continue

        # -------------------------------------------------------------- #
        # Ambiguous answer.
        # -------------------------------------------------------------- #

        if status_in in AMBIGUOUS_STATUSES:

            ambiguous += 1

            if rules.ambiguous_as == "wrong":

                m = rules.marks_wrong

                marks += m
                wrong += 1

                outcomes.append(
                    QuestionOutcome(
                        q,
                        given,
                        expected,
                        AMBIGUOUS,
                        m,
                    )
                )

            elif rules.ambiguous_as == "blank":

                m = rules.marks_blank

                marks += m
                blank += 1

                outcomes.append(
                    QuestionOutcome(
                        q,
                        given,
                        expected,
                        AMBIGUOUS,
                        m,
                    )
                )

            else:

                outcomes.append(
                    QuestionOutcome(
                        q,
                        given,
                        expected,
                        AMBIGUOUS,
                        0.0,
                    )
                )

            continue

        # -------------------------------------------------------------- #
        # Blank answer.
        # -------------------------------------------------------------- #

        if given is None:

            marks += rules.marks_blank
            blank += 1

            outcomes.append(
                QuestionOutcome(
                    q,
                    None,
                    expected,
                    UNANSWERED,
                    rules.marks_blank,
                )
            )

        # -------------------------------------------------------------- #
        # Correct answer.
        # -------------------------------------------------------------- #

        elif given.upper() in set(expected):

            marks += rules.marks_correct
            correct += 1

            outcomes.append(
                QuestionOutcome(
                    q,
                    given,
                    expected,
                    CORRECT,
                    rules.marks_correct,
                )
            )

        # -------------------------------------------------------------- #
        # Wrong answer.
        # -------------------------------------------------------------- #

        else:

            marks += rules.marks_wrong
            wrong += 1

            outcomes.append(
                QuestionOutcome(
                    q,
                    given,
                    expected,
                    WRONG,
                    rules.marks_wrong,
                )
            )

    # ------------------------------------------------------------------ #
    # Prevent negative final score if configured.
    # ------------------------------------------------------------------ #

    if rules.clamp_negative_total:

        marks = max(
            0.0,
            marks,
        )

    # ------------------------------------------------------------------ #
    # Percentage.
    # ------------------------------------------------------------------ #

    pct = (
        marks / max_marks * 100.0
        if max_marks > 0
        else 0.0
    )

    # ------------------------------------------------------------------ #
    # Final result.
    # ------------------------------------------------------------------ #

    return ScoredResult(
        roll=(
            scan.roll.value
            if scan.roll
            else None
        ),

        registration=(
            scan.registration.value
            if scan.registration
            else None
        ),

        name=name,

        correct=correct,
        wrong=wrong,
        blank=blank,
        ambiguous=ambiguous,

        total_questions=total_q,

        marks=round(
            marks,
            4,
        ),

        max_marks=round(
            max_marks,
            4,
        ),

        percentage=round(
            pct,
            4,
        ),

        grade=rules.grade_for(
            pct
        ),

        passed=(
            pct >= rules.pass_percentage
        ),

        outcomes=outcomes,
    )