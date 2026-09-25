"""Generate a printable OMR PDF from an exam configuration."""

from __future__ import annotations

import argparse
import json
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--exam-name", required=True)
    parser.add_argument("--subject", default="")
    parser.add_argument("--questions", required=True, type=int)
    parser.add_argument("--output", required=True)
    parser.add_argument("--template-output")
    args = parser.parse_args()

    engine_root = __import__("os").path.abspath(
        __import__("os").path.join(__import__("os").path.dirname(__file__), "omr_engine")
    )
    sys.path.insert(0, engine_root)

    from omr_engine import ExamConfig, build_template, generate_sheet_pdf

    config = ExamConfig(
        exam_name=args.exam_name,
        subject=args.subject,
        num_questions=args.questions,
    )
    template = build_template(config, name=args.exam_name)
    generate_sheet_pdf(template, args.output)
    if args.template_output:
        with open(args.template_output, "w", encoding="utf-8") as template_file:
            json.dump(template.to_dict(), template_file)
    json.dump({"template_id": template.template_id, "questions": args.questions}, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError) as exc:
        print(f"OMR generation failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
