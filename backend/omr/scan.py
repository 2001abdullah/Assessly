"""Small process boundary for the reusable OMR engine.

The Node API owns uploads and persistence; this script only converts one image
into the engine's JSON result.
"""

from __future__ import annotations

import argparse
import json
import os
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True)
    parser.add_argument("--template", required=True)
    parser.add_argument("--config")
    parser.add_argument("--source-name", default="")
    args = parser.parse_args()

    engine_root = os.path.abspath(
        os.path.join(os.path.dirname(__file__), "omr_engine")
    )
    sys.path.insert(0, engine_root)

    from omr_engine import EngineConfig, OMRProcessor, OMRTemplate

    template = OMRTemplate.load(args.template)
    config_data = {}
    if args.config:
        with open(args.config, "r", encoding="utf-8") as config_file:
            config_data = json.load(config_file)

    result = OMRProcessor(
        template,
        EngineConfig.from_dict(config_data),
    ).process(args.image, source_name=args.source_name)
    json.dump(result.to_dict(), sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"OMR scan failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
