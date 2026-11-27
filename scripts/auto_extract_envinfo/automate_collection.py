#!/usr/bin/env python3
"""Automate environment inspection for folders in data/results or custom dir.

Usage:
    python scripts/auto_extract_envinfo/automate_collection.py [--dir <path>] [--clean] [--force] [--target <name>]
"""

import argparse
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_RESULTS_DIR = os.path.join(HERE, "..", "..", "data", "results")
INSPECT_SCRIPT = os.path.join(HERE, "inspect_env.py")


def main():
    parser = argparse.ArgumentParser(description="Collect environment_info.json for targets.")
    parser.add_argument("--dir", "--results-dir", dest="results_dir", default=DEFAULT_RESULTS_DIR, help="Path to results directory.")
    parser.add_argument("--target", help="Specific target folder name to inspect.")
    parser.add_argument("--clean", action="store_true", default=True, help="Run 'docker compose down' after inspecting each target (default: True).")
    parser.add_argument("--no-clean", dest="clean", action="store_false", help="Leave compose projects running.")
    parser.add_argument("--force", action="store_true", help="Re-inspect even if environment_info.json already exists.")
    args = parser.parse_args()

    results_dir = os.path.abspath(args.results_dir)
    if not os.path.isdir(results_dir):
        print(f"error: results directory not found: {results_dir}", file=sys.stderr)
        return 1

    if args.target:
        targets = [args.target]
    else:
        targets = [
            d for d in sorted(os.listdir(results_dir))
            if os.path.isdir(os.path.join(results_dir, d)) and d != "newresults" and d != "__pycache__"
        ]

    total = len(targets)
    print(f"Found {total} targets to inspect in {results_dir}")

    successes = []
    failures = []
    skipped = []

    start_all = time.time()

    for idx, target_name in enumerate(targets, 1):
        target_path = os.path.join(results_dir, target_name)
        output_file = os.path.join(target_path, "environment_info.json")

        if os.path.isfile(output_file) and not args.force:
            print(f"[{idx}/{total}] SKIP: {target_name} (already has environment_info.json)")
            skipped.append(target_name)
            continue

        print(f"\n[{idx}/{total}] PROCESSING: {target_name}...")
        t0 = time.time()

        proc = subprocess.run(
            [sys.executable, INSPECT_SCRIPT, target_path],
            stdout=subprocess.PIPE,
            stderr=sys.stderr,
            text=True,
        )

        elapsed = time.time() - t0

        if proc.returncode == 0:
            try:
                data = json.loads(proc.stdout)
                with open(output_file, "w", encoding="utf-8") as f:
                    json.dump(data, f, indent=2)
                    f.write("\n")
                print(f"[{idx}/{total}] OK: {target_name} saved in {elapsed:.1f}s")
                successes.append(target_name)
            except json.JSONDecodeError as e:
                print(f"[{idx}/{total}] FAILED: {target_name} (JSON decode error: {e})", file=sys.stderr)
                failures.append((target_name, str(e)))
        else:
            print(f"[{idx}/{total}] FAILED: {target_name} (exit code {proc.returncode})", file=sys.stderr)
            failures.append((target_name, f"exit code {proc.returncode}"))

        if args.clean:
            env_dir = os.path.join(target_path, "environment")
            if os.path.isdir(env_dir):
                import hashlib
                digest = hashlib.sha1(os.path.realpath(env_dir).encode()).hexdigest()[:12]
                proj = f"env-inspect-{digest}"
                subprocess.run(
                    ["docker", "compose", "-p", proj, "down", "-v", "--remove-orphans"],
                    cwd=env_dir,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )

    total_time = time.time() - start_all
    print("\n" + "=" * 50)
    print(f"Execution finished in {total_time:.1f}s")
    print(f"Success: {len(successes)} | Skipped: {len(skipped)} | Failed: {len(failures)}")
    if failures:
        print("\nFailed targets:")
        for t, err in failures:
            print(f"  - {t}: {err}")
    print("=" * 50)
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
