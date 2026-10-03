"""Load vulnerability folders into simple, JSON-serializable records."""

from __future__ import annotations

import csv
import re
from pathlib import Path
from typing import Any


def load_vulnerabilities(
    names: list[str] | None = None, data_root: str | Path | None = None
) -> list[dict[str, Any]]:
    """Return all records, or only records in the requested folder names."""

    root = Path(data_root) if data_root is not None else _default_data_root()
    folders = _folders(root, names)
    return [_read_folder(folder) for folder in folders]


def _default_data_root() -> Path:
    return Path(__file__).resolve().parents[3] / "data"


def _folders(root: Path, names: list[str] | None) -> list[Path]:
    if not root.is_dir():
        raise FileNotFoundError(f"Data directory not found: {root}")

    if names:
        folders = [root / name for name in names]
        invalid = [folder.name for folder in folders if not (folder / "patches").is_dir()]
        if invalid:
            raise FileNotFoundError(f"Vulnerability folder not found: {', '.join(invalid)}")
        return folders

    return sorted(
        (folder for folder in root.iterdir() if (folder / "patches").is_dir()),
        key=lambda folder: folder.name,
    )


def _read_folder(folder: Path) -> dict[str, Any]:
    patches = _read_patches(folder / "patches")
    details = patches[0]["details"] if patches else None
    report = _read_report(folder / "report.csv")
    return {
        "name": folder.name,
        "nvt_oid": _nvt_oid(details) or _report_oid(report),
        "environment_info": _read_text(folder / "environment_info.txt"),
        "report": report,
        "patches": patches,
    }


def _read_patches(patch_directory: Path) -> list[dict[str, str | None]]:
    models = {
        path.name.removesuffix("_details.txt")
        for path in patch_directory.glob("*_details.txt")
    } | {
        path.name.removesuffix("_patch.sh")
        for path in patch_directory.glob("*_patch.sh")
    }
    return [
        {
            "model": model,
            "patch": _read_text(patch_directory / f"{model}_patch.sh"),
            "details": _read_text(patch_directory / f"{model}_details.txt"),
        }
        for model in sorted(models)
    ]


def _nvt_oid(details: str | None) -> str | None:
    if details is None:
        return None
    match = re.search(r"(?m)^NVT OID:[ \t]*([^\r\n]+)\r?$", details)
    return match.group(1).strip() if match else None


def _read_report(path: Path) -> list[dict[str, str | None]] | None:
    if not path.is_file():
        return None
    with path.open("r", encoding="utf-8-sig", newline="") as file:
        return list(csv.DictReader(file))


def _report_oid(report: list[dict[str, str | None]] | None) -> str | None:
    if not report:
        return None
    oid = report[0].get("NVT OID")
    return oid.strip() if oid else None


def _read_text(path: Path) -> str | None:
    return path.read_text(encoding="utf-8") if path.is_file() else None
