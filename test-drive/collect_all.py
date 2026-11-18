#!/usr/bin/env python3
"""Merge collect_findings.py and inspect_env.py output into one JSON object.

Usage:
    ./collect_all.py <target-dir>
    ./collect_all.py <target-dir>/report.csv

Prints {"vulnerability_details": [...], "environment_details": {...}}.
inspect_env.py builds and starts the target's Docker Compose project, so its
progress goes to stderr and this can take a few minutes. Only the Python
standard library is used.
"""

import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import collect_findings


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def run_inspect_env(target):
    """JSON from inspect_env.py, with its progress passed through to stderr."""
    proc = subprocess.run(
        [sys.executable, os.path.join(HERE, "inspect_env.py"), target],
        stdout=subprocess.PIPE,
        text=True,
    )
    if proc.returncode != 0:
        fail(f"inspect_env.py failed for {target}")
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        fail(f"inspect_env.py printed no JSON for {target}")


def collect(target, env_runner=run_inspect_env):
    return {
        "vulnerability_details": [
            item
            for path in collect_findings.report_paths(target)
            for item in collect_findings.findings(path)
        ],
        "environment_details": env_runner(target),
    }


def main(argv):
    if len(argv) != 2:
        print(f"usage: {os.path.basename(argv[0])} <path>", file=sys.stderr)
        return 2
    json.dump(collect(os.path.abspath(argv[1])), sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
