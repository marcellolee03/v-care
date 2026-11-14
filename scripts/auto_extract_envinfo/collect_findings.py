#!/usr/bin/env python3
"""Collect OpenVAS finding fields from a report CSV.

Usage:
    ./collect_findings.py <path>

<path> is an OpenVAS report CSV or a directory searched recursively for CSVs.
The selected columns of every result row go to stdout as a JSON array of
objects. Only the Python standard library is used.
"""

import csv
import glob
import json
import os
import sys

# JSON key -> CSV column, in the requested order.
FIELDS = {
    "port": "Port",
    "solution_type": "Solution Type",
    "nvt_name": "NVT Name",
    "summary": "Summary",
    "specific_result": "Specific Result",
    "nvt_oid": "NVT OID",
    "cves": "CVEs",
    "solution": "Solution",
    "affected_software_os": "Affected Software/OS",
    "impact": "Impact",
}


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def report_paths(target):
    if os.path.isfile(target):
        return [target]
    if not os.path.isdir(target):
        fail(f"no such file or directory: {target}")
    found = []
    for path in sorted(glob.glob(os.path.join(target, "**", "*.csv"), recursive=True)):
        with open(path, newline="", encoding="utf-8-sig") as handle:
            if "NVT OID" in (handle.readline() or ""):
                found.append(path)
    if not found:
        fail(f"no OpenVAS report CSV under {target}")
    return found


def findings(path):
    with open(path, newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            if not any(row.values()):
                continue
            item = {key: (row.get(column) or "") for key, column in FIELDS.items()}
            item["cves"] = [cve.strip() for cve in item["cves"].split(",") if cve.strip()]
            yield item


def main(argv):
    if len(argv) != 2:
        print(f"usage: {os.path.basename(argv[0])} <path>", file=sys.stderr)
        return 2
    result = [item for path in report_paths(os.path.abspath(argv[1])) for item in findings(path)]
    json.dump(result, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
