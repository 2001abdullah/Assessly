"""Process boundary for scoring an OMR scan against an answer key."""

from __future__ import annotations

import argparse
import json
import sys


def build_sheet_scan(data):
    """Reconstruct a SheetScan from scanner JSON."""

    from omr_engine.models import (
        FieldReading,
        GroupReading,
        QualityReport,
        SheetScan,
    )

    answers = []

    for item in data.get("answers", []):
        answers.append(
            GroupReading(
                key=item.get("key", ""),
                kind=item.get("kind", "question"),
                index=int(item["index"]),
                owner=item.get("owner", ""),
                value=item.get("value"),
                status=item.get("status", "blank"),
                confidence=float(item.get("confidence", 0.0)),
                scores=[
                    float(score)
                    for score in item.get("scores", [])
                ],
                labels=item.get("labels", []),
            )
        )

    roll = None
    if data.get("roll"):
        item = data["roll"]

        roll = FieldReading(
            name=item.get("name", "roll"),
            value=item.get("value"),
            digits=item.get("digits", []),
            statuses=item.get("statuses", []),
            confidence=float(item.get("confidence", 0.0)),
            needs_review=bool(
                item.get("needs_review", False)
            ),
            note=item.get("note", ""),
        )

    registration = None
    if data.get("registration"):
        item = data["registration"]

        registration = FieldReading(
            name=item.get(
                "name",
                "registration",
            ),
            value=item.get("value"),
            digits=item.get("digits", []),
            statuses=item.get("statuses", []),
            confidence=float(item.get("confidence", 0.0)),
            needs_review=bool(
                item.get("needs_review", False)
            ),
            note=item.get("note", ""),
        )

    quality_data = data.get("quality", {})

    quality = QualityReport(
        sharpness=float(
            quality_data.get("sharpness", 0.0)
        ),
        contrast=float(
            quality_data.get("contrast", 0.0)
        ),
        reprojection_error_px=float(
            quality_data.get(
                "reprojection_error_px",
                0.0,
            )
        ),
        fiducials_found=int(
            quality_data.get(
                "fiducials_found",
                0,
            )
        ),
        timing_marks_found=int(
            quality_data.get(
                "timing_marks_found",
                0,
            )
        ),
        timing_marks_expected=int(
            quality_data.get(
                "timing_marks_expected",
                0,
            )
        ),
        ink_threshold=float(
            quality_data.get(
                "ink_threshold",
                0.0,
            )
        ),
        fill_threshold=float(
            quality_data.get(
                "fill_threshold",
                0.0,
            )
        ),
        skew_deg=float(
            quality_data.get(
                "skew_deg",
                0.0,
            )
        ),
        grade=quality_data.get(
            "grade",
            "unknown",
        ),
        score=float(
            quality_data.get(
                "score",
                0.0,
            )
        ),
    )

    return SheetScan(
        ok=bool(data.get("ok", False)),
        template_id=data.get(
            "template_id",
            "",
        ),
        source=data.get(
            "source",
            "",
        ),
        roll=roll,
        registration=registration,
        answers=answers,
        quality=quality,
        warnings=data.get(
            "warnings",
            [],
        ),
        errors=data.get(
            "errors",
            [],
        ),
        qr_payload=data.get(
            "qr_payload",
            "",
        ),
        elapsed_ms=float(
            data.get(
                "elapsed_ms",
                0.0,
            )
        ),
        needs_review=bool(
            data.get(
                "needs_review",
                False,
            )
        ),
        debug_image_path=data.get(
            "debug_image_path",
            "",
        ),
    )


def main() -> int:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--scan",
        required=True,
    )

    parser.add_argument(
        "--answer-key",
        required=True,
    )

    parser.add_argument(
        "--questions",
        type=int,
        default=None,
    )

    parser.add_argument(
        "--name",
        default="",
    )

    args = parser.parse_args()

    try:
        engine_root = __import__("os").path.abspath(
            __import__("os").path.join(
                __import__("os").path.dirname(__file__),
                "omr_engine",
            )
        )

        sys.path.insert(0, engine_root)

        from omr_engine.scoring import (
            AnswerKey,
            score_sheet,
        )

        with open(
            args.scan,
            "r",
            encoding="utf-8",
        ) as file:
            scan_data = json.load(file)

        with open(
            args.answer_key,
            "r",
            encoding="utf-8",
        ) as file:
            answer_key_data = json.load(file)

        scan = build_sheet_scan(scan_data)

        answer_key = AnswerKey.from_dict(
            answer_key_data
        )

        result = score_sheet(
            scan,
            answer_key,
            num_questions=args.questions,
            name=args.name,
        )

        json.dump(
            result.to_dict(),
            sys.stdout,
            separators=(",", ":"),
        )

        sys.stdout.write("\n")

        return 0

    except Exception as exc:
        print(
            f"OMR scoring failed: {exc}",
            file=sys.stderr,
        )

        return 1


if __name__ == "__main__":
    raise SystemExit(main())