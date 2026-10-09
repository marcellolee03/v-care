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
    report_rows = _read_report(folder / "report.csv")
    patch_oids = {
        details["nvt_oid"]
        for patch in patches
        if (details := patch.get("details")) and details.get("nvt_oid")
    }
    if len(patch_oids) > 1:
        raise ValueError(f"Conflicting patch NVT OIDs for vulnerability: {folder.name}")
    nvt_oid = next(iter(patch_oids), None) or _report_oid(report_rows)
    return {
        "name": folder.name,
        "nvt_oid": nvt_oid,
        "environment_info": _read_environment_info(folder / "environment_info.txt"),
        "report": _matching_report(report_rows, nvt_oid, folder.name),
        "patches": patches,
    }


def _read_patches(patch_directory: Path) -> list[dict[str, Any]]:
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
            "details": _read_patch_details(
                _read_text(patch_directory / f"{model}_details.txt"), model
            ),
        }
        for model in sorted(models)
    ]


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


def _matching_report(
    report: list[dict[str, str | None]] | None,
    nvt_oid: str | None,
    vulnerability_name: str,
) -> dict[str, str | None] | None:
    if report is None:
        return None
    if nvt_oid is None:
        raise ValueError(f"NVT OID not found for vulnerability: {vulnerability_name}")

    matches = [row for row in report if (row.get("NVT OID") or "").strip() == nvt_oid]
    if len(matches) != 1:
        raise ValueError(
            f"Expected one report row for {vulnerability_name} ({nvt_oid}), "
            f"found {len(matches)}"
        )
    return matches[0]


def _read_environment_info(path: Path) -> dict[str, Any] | None:
    text = _read_text(path)
    return _parse_environment_info(text) if text is not None else None


def _parse_environment_info(text: str) -> dict[str, Any]:
    sections: dict[str, list[str]] = {}
    unparsed_lines: list[str] = []
    current_section: str | None = None
    header = re.compile(r"^\s*(?:\*\*(.+?)\*\*|===\s*(.+?)\s*===)\s*$")

    for line in text.splitlines():
        match = header.match(line)
        if match:
            current_section = (match.group(1) or match.group(2)).strip()
            sections.setdefault(current_section, [])
        elif current_section is not None:
            if line.strip():
                sections[current_section].append(line.strip())
        elif line.strip():
            unparsed_lines.append(line)

    known_sections = {
        "OS INFO",
        "KERNEL INFORMATION",
        "USER INFO",
        "PACKAGE MANAGER",
        "TOOLS",
    }
    result: dict[str, Any] = {
        "os_info": _parse_key_values(sections.get("OS INFO", []), "="),
        "user_info": _parse_user_info(sections.get("USER INFO", [])),
        "package_manager": _single_value(sections.get("PACKAGE MANAGER", [])),
        "tools": sections.get("TOOLS", []),
    }
    if "KERNEL INFORMATION" in sections:
        result["kernel_information"] = _parse_key_values(
            sections["KERNEL INFORMATION"], ":"
        )

    extra_sections = {
        name: lines for name, lines in sections.items() if name not in known_sections
    }
    if extra_sections:
        result["extra_sections"] = extra_sections
    if unparsed_lines:
        result["unparsed_lines"] = unparsed_lines
    return result


def _parse_key_values(lines: list[str], separator: str) -> dict[str, Any]:
    values: dict[str, Any] = {}
    for line in lines:
        if separator not in line:
            values.setdefault("unparsed_lines", []).append(line)
            continue
        key, value = line.split(separator, 1)
        normalized_key = key.strip().lower()
        normalized_value = value.strip()
        if len(normalized_value) >= 2 and normalized_value[0] == normalized_value[-1] == '"':
            normalized_value = normalized_value[1:-1]
        if separator == ":" and normalized_value.startswith("(") and normalized_value.endswith(")"):
            normalized_value = normalized_value[1:-1]
        values[normalized_key] = normalized_value
    return values


def _parse_user_info(lines: list[str]) -> dict[str, Any] | None:
    if not lines:
        return None
    line = " ".join(lines)
    match = re.fullmatch(
        r"uid=(\d+)\(([^)]*)\)\s+gid=(\d+)\(([^)]*)\)\s+groups=(.*)", line
    )
    if not match:
        return {"raw": line}

    groups = []
    for group in match.group(5).split(","):
        group_match = re.fullmatch(r"(\d+)\(([^)]*)\)", group.strip())
        if not group_match:
            return {"raw": line}
        groups.append({"gid": int(group_match.group(1)), "name": group_match.group(2)})
    return {
        "uid": int(match.group(1)),
        "username": match.group(2),
        "gid": int(match.group(3)),
        "group": match.group(4),
        "groups": groups,
    }


def _single_value(lines: list[str]) -> str | list[str] | None:
    if not lines:
        return None
    return lines[0] if len(lines) == 1 else lines


def _read_patch_details(text: str | None, expected_model: str) -> dict[str, Any] | None:
    if text is None:
        return None

    fields: dict[str, str] = {}
    unparsed_lines: list[str] = []
    for line in text.splitlines():
        if not line.strip() or line.strip() == "=== PATCH GENERATION DETAILS ===":
            continue
        if ":" not in line:
            unparsed_lines.append(line)
            continue
        key, value = line.split(":", 1)
        fields[key.strip()] = value.strip()

    model = fields.pop("Model", None)
    if model is not None and model != expected_model:
        raise ValueError(f"Patch model mismatch: expected {expected_model}, found {model}")

    elapsed = fields.pop("Time elapsed", None)
    elapsed_seconds: float | None = None
    if elapsed:
        match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)\s+seconds", elapsed)
        if match:
            elapsed_seconds = float(match.group(1))
        else:
            fields["Time elapsed"] = elapsed

    functional = fields.pop("Patch functional?", None)
    result: dict[str, Any] = {
        "nvt_oid": fields.pop("NVT OID", None),
        "vulnerability": fields.pop("Vulnerability", None),
        "time_elapsed_seconds": elapsed_seconds,
        "functional": functional or None,
    }
    if fields:
        result["extra"] = fields
    if unparsed_lines:
        result["unparsed_lines"] = unparsed_lines
    return result


def _read_text(path: Path) -> str | None:
    return path.read_text(encoding="utf-8") if path.is_file() else None
