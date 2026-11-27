"""Export an OpenVAS report in Greenbone's CSV Results format."""

import argparse
import base64
import os
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path
from uuid import UUID

from dotenv import load_dotenv

if __package__:
    from .create_and_start_scan import gmp_request
else:
    from create_and_start_scan import gmp_request

ROOT = Path(__file__).resolve().parents[2]


def export_csv(report_id, manager, username, password):
    formats = gmp_request(
        manager, username, password, '<get_report_formats filter="rows=-1"/>'
    )
    csv_format = formats.find("report_format[name='CSV Results'][@id]")
    if csv_format is None:
        raise ValueError("Greenbone's CSV Results report format is unavailable")

    request = ET.Element(
        "get_reports",
        report_id=str(report_id),
        format_id=csv_format.attrib["id"],
        details="1",
        ignore_pagination="1",
    )
    response = gmp_request(
        manager, username, password, ET.tostring(request, encoding="unicode")
    )
    report = response.find("report")
    if report is None or report.get("extension") != "csv":
        raise ValueError(f"Greenbone did not return a CSV for report {report_id}")

    payload = "".join([report.text or "", *(child.tail or "" for child in report)])
    if not payload.strip():
        raise ValueError(
            f"Greenbone returned an empty CSV payload for report {report_id}"
        )
    return base64.b64decode("".join(payload.split()), validate=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report_id", type=UUID, help="Greenbone report UUID")
    parser.add_argument("origin", help="Origin directory under data")
    parser.add_argument("vulnerability_name", help="Vulnerability case directory")
    parser.add_argument("author", help="Patch author used in the CSV filename")
    args = parser.parse_args()
    for name in (args.origin, args.vulnerability_name, args.author):
        if not name or name == ".." or Path(name).name != name:
            parser.error(f"expected a single path component, got {name!r}")

    output = (
        ROOT
        / "data"
        / args.origin
        / args.vulnerability_name
        / "results"
        / "proof"
        / f"{args.author}.csv"
    )

    load_dotenv(ROOT / ".env", interpolate=False)
    password = os.environ.get("GMP_PASSWORD")
    if not password:
        parser.error("Set GMP_PASSWORD in the project .env file or environment")
    try:
        data = export_csv(
            args.report_id,
            os.environ.get("GVMD_CONTAINER", "greenbone-community-edition-gvmd-1"),
            os.environ.get("GMP_USERNAME", "admin"),
            password,
        )
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open("xb") as handle:
            handle.write(data)
    except (OSError, ValueError, ET.ParseError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"OpenVAS export failed: {error}\n")
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
