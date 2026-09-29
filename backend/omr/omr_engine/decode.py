"""Assemble digit-column readings into roll and registration numbers."""

from __future__ import annotations

from typing import Dict, List, Optional

from .config import EngineConfig
from .models import BLANK, MARKED, FieldReading, GroupReading
from .template import OMRTemplate


def decode_field(template: OMRTemplate, field_name: str,
                 readings: Dict[str, GroupReading], cfg: EngineConfig) -> FieldReading:
    """
    Build a numeric field from its digit columns.

    Blank columns at either end are tolerated: a 5-digit roll number written
    into a 7-column grid leaves the unused columns empty, on the left or the
    right depending on how the student aligned it, which is normal rather than
    an error.  A blank in the *middle* of the number, or a column that is faint
    or double-marked, is a real problem and sends the sheet to review.
    """
    spec = template.fields.get(field_name)
    if spec is None:
        return FieldReading(field_name, None, [], [], 0.0, False, "field not on this template")

    digits: List[Optional[str]] = []
    statuses: List[str] = []
    confs: List[float] = []
    for key in spec.group_keys:
        r = readings.get(key)
        if r is None:
            digits.append(None)
            statuses.append("missing")
            confs.append(0.0)
            continue
        statuses.append(r.status)
        confs.append(r.confidence)
        digits.append(r.value if r.status == MARKED else None)

    note = ""
    needs_review = False

    # strip runs of unused (truly blank) columns at both ends
    lead = 0
    while lead < len(digits) and digits[lead] is None and statuses[lead] == BLANK:
        lead += 1
    end = len(digits)
    while end > lead and digits[end - 1] is None and statuses[end - 1] == BLANK:
        end -= 1
    body = digits[lead:end]
    unused = lead + (len(digits) - end)

    if lead == len(digits):
        value = None
        needs_review = True
        note = "no digits marked"
    elif all(d is not None for d in body):
        value = "".join(d for d in body if d is not None)  # type: ignore[arg-type]
        if unused:
            note = f"{unused} unused column(s) left blank"
    else:
        value = None
        needs_review = True
        bad = [i + lead + 1 for i, d in enumerate(body) if d is None]
        note = f"unreadable digit column(s): {', '.join(map(str, bad))}"

    conf = min(confs) if confs else 0.0
    if value is not None and conf < cfg.review_confidence:
        needs_review = True
        note = note or "low confidence"

    return FieldReading(
        name=field_name,
        value=value,
        digits=digits,
        statuses=statuses,
        confidence=conf,
        needs_review=needs_review,
        note=note,
    )
