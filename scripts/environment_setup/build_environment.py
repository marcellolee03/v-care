import argparse
import csv
import json
import subprocess
import sys
from pathlib import Path

DATA_ROOT = Path(__file__).resolve().parents[2] / "data"
COMPOSE_NAMES = (
    "compose.yaml",
    "compose.yml",
    "docker-compose.yml",
    "docker-compose.yaml",
)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build a vulnerability's Docker Compose environment and print its reported ports."
    )
    parser.add_argument("origin", help="Origin directory name under data")
    parser.add_argument(
        "vulnerability_name", help="Case directory name under data/<origin>"
    )
    parser.add_argument(
        "port",
        nargs="?",
        default="-",
        help="Replace the published host port listed in report.csv, or - to keep it",
    )
    parser.add_argument(
        "name", nargs="?", help="Compose project name (default: resolved by Compose)"
    )
    args = parser.parse_args()

    port_override = None
    if args.port != "-":
        if not args.port.isascii() or not args.port.isdecimal() or len(args.port) > 5:
            parser.error("port must be an integer from 1 to 65535")
        port_override = int(args.port)
        if not 1 <= port_override <= 65535:
            parser.error("port must be an integer from 1 to 65535")

    for name in (args.origin, args.vulnerability_name):
        if not name or name == ".." or Path(name).name != name:
            parser.error(f"expected a directory name, got {name!r}")

    case = DATA_ROOT / args.origin / args.vulnerability_name
    if not case.is_dir():
        parser.error(f"no case directory at {case}")

    environment = case / "environment"
    compose_file = next(
        (
            environment / name
            for name in COMPOSE_NAMES
            if (environment / name).is_file()
        ),
        None,
    )
    if compose_file is None:
        parser.error(f"no Docker Compose file in {environment}")

    report = case / "report.csv"
    try:
        with report.open(encoding="utf-8-sig", newline="") as handle:
            values = [(row.get("Port") or "").strip() for row in csv.DictReader(handle)]
    except (OSError, UnicodeError, csv.Error) as exc:
        parser.error(f"could not read {report}: {exc}")

    ports = dict.fromkeys(
        int(value) for value in values if value.isdecimal() and 1 <= int(value) <= 65535
    )
    if not ports:
        parser.error(f"no valid port in the Port column of {report}")

    compose = ["docker", "compose", "-f", str(compose_file)]
    if args.name is not None:
        compose.extend(["-p", args.name])

    override = None
    output_ports = list(ports)
    try:
        if port_override is not None:
            config = subprocess.run(
                [*compose, "config", "--format", "json", "--no-env-resolution"],
                cwd=environment,
                stdout=subprocess.PIPE,
                text=True,
                check=True,
            )
            services = json.loads(config.stdout)["services"]
            matches = [
                (service, binding)
                for service, spec in services.items()
                for binding in spec.get("ports", [])
                for reported_port in ports
                if binding.get("published") == str(reported_port)
            ]
            if len(matches) != 1:
                parser.error(
                    "port override requires exactly one published port matching the report"
                )

            service, binding = matches[0]
            binding["published"] = str(port_override)
            bindings = json.dumps(services[service]["ports"]).replace("$", "$$")
            override = f"services:\n  {json.dumps(service)}:\n    ports: !override {bindings}\n"
            compose.extend(["-f", "-"])
            output_ports = [port_override]

        result = subprocess.run(
            [*compose, "up", "--build", "--wait"],
            cwd=environment,
            input=override,
            stdout=sys.stderr,
            text=True,
            check=False,
        )
    except subprocess.CalledProcessError as exc:
        return exc.returncode
    except OSError as exc:
        parser.exit(1, f"could not run Docker Compose: {exc}\n")
    if result.returncode:
        return result.returncode

    for port in output_ports:
        print(port)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
