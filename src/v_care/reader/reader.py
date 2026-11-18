"""Load vulnerability folders into simple, JSON-serializable records."""

from __future__ import annotations

import csv
import json
import re
from contextlib import suppress
from pathlib import Path
from typing import Any

SOURCES = ("web", "vulhub", "pop_vm")


def load_vulnerabilities(
    names: list[str] | None = None,
    data_root: str | Path | None = None,
    include_new_batch: bool = True,
    has_oid: bool | None = None,
    has_cve: bool | None = None,
    has_env: bool | None = None,
) -> list[dict[str, Any]]:
    """Return all records, or only records matching requested criteria."""

    root = Path(data_root) if data_root is not None else _default_data_root()
    folders = _folders(root, names, include_new_batch=include_new_batch)
    records = [_read_folder(folder) for folder in folders]

    if has_oid is not None:
        records = [record for record in records if record["has_oid"] is has_oid]
    if has_cve is not None:
        records = [record for record in records if record["has_cve"] is has_cve]
    if has_env is not None:
        records = [
            record
            for record in records
            if (record["environment_details"] is not None) is has_env
        ]

    return records


def _default_data_root() -> Path:
    return Path(__file__).resolve().parents[3] / "data"


def _folders(
    root: Path,
    names: list[str] | None,
    include_new_batch: bool,
) -> list[Path]:
    if not root.is_dir():
        raise FileNotFoundError(f"Data directory not found: {root}")

    folders: list[Path] = []

    for source in root.iterdir():
        if source.name not in SOURCES or not source.is_dir():
            continue
        if source.name == "web" and not include_new_batch:
            continue
        folders.extend(
            folder for folder in source.iterdir() if (folder / "report.csv").is_file()
        )

    if not names:
        return sorted(folders, key=lambda folder: folder.name)

    folder_map = {folder.name: folder for folder in folders}
    folder_map.update(
        {folder.relative_to(root).as_posix(): folder for folder in folders}
    )
    invalid = [name for name in names if name not in folder_map]
    if invalid:
        raise FileNotFoundError(f"Vulnerability folder not found: {', '.join(invalid)}")
    return [folder_map[name] for name in names]


def _read_folder(folder: Path) -> dict[str, Any]:
    report = _read_report(folder / "report.csv")
    oid = report.get("NVT OID") if report is not None else None
    if report is not None and not oid:
        raise ValueError(f"NVT OID not found for vulnerability: {folder.name}")
    nvt_oid = oid.strip() if oid else None

    cves = (report.get("CVEs") or "") if report else ""
    has_cve = bool(
        re.search(r"CVE-\d{4}-\d+", cves, re.IGNORECASE)
        or (nvt_oid and re.match(r"^CVE-\d{4}-\d+", nvt_oid, re.IGNORECASE))
    )

    return {
        "name": folder.name,
        "source": folder.parent.name,
        "nvt_oid": nvt_oid,
        "has_oid": bool(nvt_oid and nvt_oid.startswith("1.3.6.1.")),
        "has_cve": has_cve,
        "environment_details": _read_environment_info(folder),
        "vulnerability_details": report,
    }


def _read_report(path: Path) -> dict[str, str | None] | None:
    if not path.is_file():
        return None
    with path.open("r", encoding="utf-8-sig", newline="") as file:
        return next(csv.DictReader(file), {})


def _read_environment_info(folder: Path) -> dict[str, Any] | None:
    """Read the environment JSON if available."""
    json_path = folder / "environment_info.json"
    if json_path.is_file():
        with suppress(OSError, ValueError, RecursionError):
            return json.loads(json_path.read_text(encoding="utf-8"))

    return None
