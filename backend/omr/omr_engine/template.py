"""
Template model for OMR sheets.

Everything in this module is expressed in **millimetres on the physical page**,
with the origin at the top-left corner of the page and +y pointing *down*.

The template is the single source of truth shared by two consumers:

  * :mod:`omr_engine.generator` -- draws the printable PDF from these coordinates.
  * :mod:`omr_engine.pipeline`  -- samples the scanned image at these coordinates.

Because both sides read the *same* explicit coordinates, there is no layout logic
to keep in sync and no opportunity for the printer and the scanner to disagree.
Layout maths happens exactly once, in :mod:`omr_engine.layout`, and its output is
frozen into the template as explicit bubble centres.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field, asdict
from typing import Any, Dict, List, Optional, Sequence, Tuple

TEMPLATE_SCHEMA_VERSION = 1

# --------------------------------------------------------------------------- #
# Paper sizes
# --------------------------------------------------------------------------- #

PAGE_SIZES_MM: Dict[str, Tuple[float, float]] = {
    "A4": (210.0, 297.0),
    "A3": (297.0, 420.0),
    "LETTER": (215.9, 279.4),
    "LEGAL": (215.9, 355.6),
}

DEFAULT_OPTION_LABELS = ["A", "B", "C", "D", "E", "F"]


# --------------------------------------------------------------------------- #
# Primitives
# --------------------------------------------------------------------------- #


@dataclass
class Bubble:
    """A single printed bubble."""

    x_mm: float
    y_mm: float
    r_mm: float
    label: str
    value: str  # "A".."E" for questions, "0".."9" for digit columns

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "Bubble":
        return cls(**d)


@dataclass
class BubbleGroup:
    """
    A mutually-exclusive set of bubbles.

    One group == one decision the scanner has to make: which single bubble (if
    any) did the candidate fill.  A question is a group; so is one digit column
    of the roll number.
    """

    key: str  # "q17", "roll.d3", "reg.d0"
    kind: str  # "question" | "digit"
    index: int  # question number (1-based) or digit position (0-based, leftmost)
    bubbles: List[Bubble] = field(default_factory=list)
    owner: str = ""  # "questions" | "roll" | "registration"

    def to_dict(self) -> Dict[str, Any]:
        return {
            "key": self.key,
            "kind": self.kind,
            "index": self.index,
            "owner": self.owner,
            "bubbles": [b.to_dict() for b in self.bubbles],
        }

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "BubbleGroup":
        return cls(
            key=d["key"],
            kind=d["kind"],
            index=d["index"],
            owner=d.get("owner", ""),
            bubbles=[Bubble.from_dict(b) for b in d["bubbles"]],
        )

    @property
    def labels(self) -> List[str]:
        return [b.value for b in self.bubbles]


@dataclass
class Fiducial:
    """
    A solid black registration square with a white quiet zone around it.

    Placed at the four corners.  The scanner finds these to compute the
    homography from page-millimetres to image-pixels.
    """

    name: str  # "tl" | "tr" | "bl" | "br"
    x_mm: float  # centre
    y_mm: float  # centre
    size_mm: float  # side length of the black square
    quiet_mm: float  # white margin kept clear around the square

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "Fiducial":
        return cls(**d)


@dataclass
class TimingTrack:
    """
    A column of small black rectangles, one per bubble row, printed down an edge.

    This is what physical OMR readers use for row registration.  We use it the
    same way: after the coarse homography, the detected timing marks give an
    independent, per-row vertical correction that absorbs paper stretch, printer
    scaling and residual skew.
    """

    name: str  # "left" | "right"
    x_mm: float  # centre x of the track
    w_mm: float
    h_mm: float
    y_positions_mm: List[float] = field(default_factory=list)  # centres, top to bottom

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "TimingTrack":
        return cls(**d)


@dataclass
class TextBox:
    """A printed label or a hand-write box (never read by the scanner)."""

    x_mm: float
    y_mm: float
    w_mm: float
    h_mm: float
    text: str = ""
    font_size: float = 8.0
    bold: bool = False
    box: bool = False
    align: str = "left"  # left | center | right

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "TextBox":
        return cls(**d)


@dataclass
class FieldSpec:
    """A multi-digit numeric field made of digit-column groups."""

    name: str  # "roll" | "registration"
    title: str
    digits: int
    group_keys: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "FieldSpec":
        return cls(**d)


# --------------------------------------------------------------------------- #
# Exam configuration (the user-facing knobs)
# --------------------------------------------------------------------------- #


@dataclass
class ExamConfig:
    """What the operator fills in on the 'New Exam' screen."""

    exam_name: str = "Examination"
    subject: str = ""
    exam_code: str = ""
    num_questions: int = 100
    num_options: int = 4
    option_labels: Optional[List[str]] = None
    roll_digits: int = 7
    registration_digits: int = 10
    include_name_box: bool = True
    page_size: str = "A4"
    instructions: str = (
        "Use HB pencil or black/blue ball pen. Fill the bubble completely. "
        "Do not fold or stain the sheet. Erase cleanly to change an answer."
    )

    # scoring, carried on the template so a printed sheet documents its own rules
    marks_correct: float = 1.0
    marks_wrong: float = 0.0
    marks_blank: float = 0.0

    def resolved_labels(self) -> List[str]:
        if self.option_labels:
            labels = list(self.option_labels)
        else:
            labels = DEFAULT_OPTION_LABELS[: self.num_options]
        if len(labels) != self.num_options:
            raise ValueError(
                f"option_labels has {len(labels)} entries but num_options={self.num_options}"
            )
        return labels

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "ExamConfig":
        known = {f for f in cls.__dataclass_fields__}  # type: ignore[attr-defined]
        return cls(**{k: v for k, v in d.items() if k in known})


# --------------------------------------------------------------------------- #
# The template itself
# --------------------------------------------------------------------------- #


@dataclass
class OMRTemplate:
    template_id: str
    name: str
    page_w_mm: float
    page_h_mm: float
    config: ExamConfig
    fiducials: List[Fiducial] = field(default_factory=list)
    timing_tracks: List[TimingTrack] = field(default_factory=list)
    groups: List[BubbleGroup] = field(default_factory=list)
    fields: Dict[str, FieldSpec] = field(default_factory=dict)
    texts: List[TextBox] = field(default_factory=list)
    bubble_r_mm: float = 1.9
    qr_x_mm: float = 0.0
    qr_y_mm: float = 0.0
    qr_size_mm: float = 16.0
    qr_payload: str = ""
    schema_version: int = TEMPLATE_SCHEMA_VERSION
    # The rectangle (in mm) that fiducial centres span; the engine warps to this.
    roi: Tuple[float, float, float, float] = (0.0, 0.0, 0.0, 0.0)
    meta: Dict[str, Any] = field(default_factory=dict)

    # -- lookups ---------------------------------------------------------- #

    def group(self, key: str) -> BubbleGroup:
        for g in self.groups:
            if g.key == key:
                return g
        raise KeyError(key)

    def question_groups(self) -> List[BubbleGroup]:
        return sorted(
            (g for g in self.groups if g.owner == "questions"), key=lambda g: g.index
        )

    def field_groups(self, field_name: str) -> List[BubbleGroup]:
        spec = self.fields[field_name]
        return [self.group(k) for k in spec.group_keys]

    def fiducial(self, name: str) -> Fiducial:
        for f in self.fiducials:
            if f.name == name:
                return f
        raise KeyError(name)

    @property
    def option_labels(self) -> List[str]:
        return self.config.resolved_labels()

    @property
    def num_questions(self) -> int:
        return self.config.num_questions

    def total_bubbles(self) -> int:
        return sum(len(g.bubbles) for g in self.groups)

    # -- serialisation ---------------------------------------------------- #

    def to_dict(self) -> Dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "template_id": self.template_id,
            "name": self.name,
            "page_w_mm": self.page_w_mm,
            "page_h_mm": self.page_h_mm,
            "bubble_r_mm": self.bubble_r_mm,
            "config": self.config.to_dict(),
            "fiducials": [f.to_dict() for f in self.fiducials],
            "timing_tracks": [t.to_dict() for t in self.timing_tracks],
            "groups": [g.to_dict() for g in self.groups],
            "fields": {k: v.to_dict() for k, v in self.fields.items()},
            "texts": [t.to_dict() for t in self.texts],
            "qr_x_mm": self.qr_x_mm,
            "qr_y_mm": self.qr_y_mm,
            "qr_size_mm": self.qr_size_mm,
            "qr_payload": self.qr_payload,
            "roi": list(self.roi),
            "meta": self.meta,
        }

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "OMRTemplate":
        if d.get("schema_version", 1) > TEMPLATE_SCHEMA_VERSION:
            raise ValueError(
                f"template schema v{d['schema_version']} is newer than this engine "
                f"(v{TEMPLATE_SCHEMA_VERSION}); upgrade omr_engine"
            )
        roi = tuple(d.get("roi", (0, 0, 0, 0)))  # type: ignore[assignment]
        return cls(
            template_id=d["template_id"],
            name=d["name"],
            page_w_mm=d["page_w_mm"],
            page_h_mm=d["page_h_mm"],
            bubble_r_mm=d.get("bubble_r_mm", 1.9),
            config=ExamConfig.from_dict(d["config"]),
            fiducials=[Fiducial.from_dict(x) for x in d.get("fiducials", [])],
            timing_tracks=[TimingTrack.from_dict(x) for x in d.get("timing_tracks", [])],
            groups=[BubbleGroup.from_dict(x) for x in d.get("groups", [])],
            fields={k: FieldSpec.from_dict(v) for k, v in d.get("fields", {}).items()},
            texts=[TextBox.from_dict(x) for x in d.get("texts", [])],
            qr_x_mm=d.get("qr_x_mm", 0.0),
            qr_y_mm=d.get("qr_y_mm", 0.0),
            qr_size_mm=d.get("qr_size_mm", 16.0),
            qr_payload=d.get("qr_payload", ""),
            roi=roi,  # type: ignore[arg-type]
            meta=d.get("meta", {}),
            schema_version=d.get("schema_version", TEMPLATE_SCHEMA_VERSION),
        )

    def to_json(self, indent: int = 2) -> str:
        return json.dumps(self.to_dict(), indent=indent)

    @classmethod
    def from_json(cls, text: str) -> "OMRTemplate":
        return cls.from_dict(json.loads(text))

    def save(self, path: str) -> None:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(self.to_json())

    @classmethod
    def load(cls, path: str) -> "OMRTemplate":
        with open(path, "r", encoding="utf-8") as fh:
            return cls.from_json(fh.read())

    def checksum(self) -> str:
        """Stable hash of the geometry -- used to detect template/scan mismatch."""
        payload = json.dumps(self.to_dict(), sort_keys=True).encode("utf-8")
        return hashlib.sha256(payload).hexdigest()[:16]

    # -- validation ------------------------------------------------------- #

    def validate(self) -> List[str]:
        """Return a list of problems; empty list means the template is sane."""
        problems: List[str] = []
        if len(self.fiducials) != 4:
            problems.append(f"expected 4 fiducials, found {len(self.fiducials)}")
        names = {f.name for f in self.fiducials}
        if names != {"tl", "tr", "bl", "br"}:
            problems.append(f"fiducial names must be tl/tr/bl/br, got {sorted(names)}")

        qs = self.question_groups()
        if len(qs) != self.config.num_questions:
            problems.append(
                f"{len(qs)} question groups but config says {self.config.num_questions}"
            )
        for g in qs:
            if len(g.bubbles) != self.config.num_options:
                problems.append(
                    f"{g.key} has {len(g.bubbles)} bubbles, expected {self.config.num_options}"
                )

        for fname, spec in self.fields.items():
            if len(spec.group_keys) != spec.digits:
                problems.append(
                    f"field {fname}: {len(spec.group_keys)} columns but digits={spec.digits}"
                )
            for k in spec.group_keys:
                try:
                    g = self.group(k)
                except KeyError:
                    problems.append(f"field {fname} references missing group {k}")
                    continue
                if len(g.bubbles) != 10:
                    problems.append(f"digit column {k} has {len(g.bubbles)} bubbles, expected 10")

        # bubbles must be on the page and inside the fiducial ROI
        x0, y0, x1, y1 = self.roi
        for g in self.groups:
            for b in g.bubbles:
                if not (0 <= b.x_mm <= self.page_w_mm and 0 <= b.y_mm <= self.page_h_mm):
                    problems.append(f"bubble {g.key}:{b.value} is off the page")
                elif x1 > x0 and not (x0 <= b.x_mm <= x1 and y0 <= b.y_mm <= y1):
                    problems.append(f"bubble {g.key}:{b.value} lies outside the fiducial ROI")

        # no two bubbles may overlap
        pts: List[Tuple[float, float, float, str]] = [
            (b.x_mm, b.y_mm, b.r_mm, f"{g.key}:{b.value}")
            for g in self.groups
            for b in g.bubbles
        ]
        pts.sort(key=lambda p: (p[1], p[0]))
        for i in range(len(pts)):
            xi, yi, ri, ni = pts[i]
            for j in range(i + 1, len(pts)):
                xj, yj, rj, nj = pts[j]
                if yj - yi > (ri + rj):
                    break
                if (xi - xj) ** 2 + (yi - yj) ** 2 < (ri + rj) ** 2:
                    problems.append(f"bubbles {ni} and {nj} overlap")
        return problems


def sequence_to_dict(seq: Sequence[Any]) -> List[Any]:
    return [s.to_dict() if hasattr(s, "to_dict") else s for s in seq]
