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

    # Filtros de subconjunto de dados
    oid_group = parser.add_mutually_exclusive_group()
    oid_group.add_argument(
        "--with-oid",
        dest="has_oid",
        action="store_true",
        default=None,
        help="Filter only vulnerabilities with standard OpenVAS NVT OID (1.3.6.1...).",
    )
    oid_group.add_argument(
        "--without-oid",
        dest="has_oid",
        action="store_false",
        default=None,
        help="Filter only vulnerabilities without standard NVT OID (e.g. CVE-based).",
    )

    cve_group = parser.add_mutually_exclusive_group()
    cve_group.add_argument(
        "--with-cve",
        dest="has_cve",
        action="store_true",
        default=None,
        help="Filter only vulnerabilities with an associated CVE.",
    )
    cve_group.add_argument(
        "--without-cve",
        dest="has_cve",
        action="store_false",
        default=None,
        help="Filter only vulnerabilities without an associated CVE.",
    )

    env_group = parser.add_mutually_exclusive_group()
    env_group.add_argument(
        "--with-env",
        dest="has_env",
        action="store_true",
        default=None,
        help="Filter only vulnerabilities with environment_info.txt.",
    )
    env_group.add_argument(
        "--without-env",
        dest="has_env",
        action="store_false",
        default=None,
        help="Filter only vulnerabilities without environment_info.txt.",
    )

    parser.add_argument(
        "--exclude-new-batch",
        action="store_true",
        help="Exclude the new batch of 111 vulnerabilities, loading only root data folders.",
    )
    args = parser.parse_args()

    try:
        records = load_vulnerabilities(
            names=args.names,
            include_new_batch=not args.exclude_new_batch,
            has_oid=args.has_oid,
            has_cve=args.has_cve,
            has_env=args.has_env,
        )
    except (FileNotFoundError, ValueError) as error:
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
