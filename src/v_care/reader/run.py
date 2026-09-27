"""Print selected vulnerability records as JSONL."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from v_care.reader.reader import load_vulnerabilities


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Print V-Care vulnerability records as JSONL."
    )
    parser.add_argument(
        "names",
        nargs="*",
        help="Optional vulnerability folder names. Without them, returns all records.",
    )
    parser.add_argument(
        "--stdout",
        action="store_true",
        help="Print JSONL to the terminal instead of writing a file.",
    )
    args = parser.parse_args()

    try:
        records = load_vulnerabilities(args.names)
    except FileNotFoundError as error:
        parser.error(str(error))

    lines = [json.dumps(record, ensure_ascii=False) for record in records]
    if args.stdout:
        print("\n".join(lines))
        return

    default_name = "vulnerabilities.jsonl" if not args.names else "selected-vulnerabilities.jsonl"
    output = Path("output") / default_name
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Saved {len(records)} vulnerability record(s) to {output}")


if __name__ == "__main__":
    main()
