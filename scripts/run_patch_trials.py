#!/usr/bin/env -S uv run
"""Build, patch, scan, and export both remediation trials for a case."""

import argparse
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
ROOT = SCRIPTS.parent
TRIALS = (
    ("6767", "deepseek_flash", "deepseek_scan"),
    ("6868", "claude_haiku", "haiku_scan"),
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("origin")
    parser.add_argument("vulnerability_name")
    args = parser.parse_args()
    for name in (args.origin, args.vulnerability_name):
        if not name or name == ".." or Path(name).name != name:
            parser.error(f"expected a directory name, got {name!r}")

    patches = Path("data") / args.origin / args.vulnerability_name / "patches"
    for _, patch, _ in TRIALS:
        path = patches / f"{patch}.sh"
        if not (ROOT / path).is_file():
            parser.error(f"patch file does not exist: {path}")

    def run(script, *arguments, capture_stdout=False):
        return subprocess.run(
            [sys.executable, str(SCRIPTS / script), *arguments],
            cwd=ROOT,
            check=True,
            stdout=subprocess.PIPE if capture_stdout else None,
            text=True,
        )

    def scan_and_export(port, author, task_name):
        scan = run(
            "patch_validation/create_and_start_scan.py",
            port,
            "--task-name",
            task_name,
            "--report-id-only",
            capture_stdout=True,
        )
        report_id = scan.stdout.strip()
        if not report_id:
            raise RuntimeError(f"{task_name} completed without a report ID")
        run(
            "patch_validation/export_report.py",
            report_id,
            args.origin,
            args.vulnerability_name,
            author,
        )

    environment = ROOT / patches.parent / "environment"

    def containers(project):
        output = subprocess.check_output(
            [
                "docker",
                "ps",
                "--all",
                "--quiet",
                "--no-trunc",
                "--filter",
                f"label=com.docker.compose.project={project}",
                "--filter",
                f"label=com.docker.compose.project.working_dir={environment}",
            ],
            cwd=ROOT,
            text=True,
        )
        return set(output.split())

    trial_containers = set()
    cleanup_status = 0
    try:
        for port, patch, _ in TRIALS:
            try:
                run(
                    "environment_setup/build_environment.py",
                    args.origin,
                    args.vulnerability_name,
                    port,
                    patch,
                )
            finally:
                trial_containers.update(containers(patch))
        for port, patch, _ in TRIALS:
            run("environment_setup/apply_patch.py", port, str(patches / f"{patch}.sh"))
        # Each scan waits for its service to become reachable after restart.
        with ThreadPoolExecutor(max_workers=len(TRIALS)) as executor:
            scans = [
                executor.submit(scan_and_export, port, author, task_name)
                for port, author, task_name in TRIALS
            ]
            for scan in scans:
                scan.result()
    except subprocess.CalledProcessError as exc:
        parser.exit(
            exc.returncode,
            f"{Path(exc.cmd[1]).name} exited with status {exc.returncode}\n",
        )
    except RuntimeError as exc:
        parser.exit(1, f"{exc}\n")
    finally:
        if trial_containers:
            cleanup_status = subprocess.run(
                ["docker", "rm", "--force", *sorted(trial_containers)],
                cwd=ROOT,
                check=False,
            ).returncode
    return cleanup_status


if __name__ == "__main__":
    raise SystemExit(main())
