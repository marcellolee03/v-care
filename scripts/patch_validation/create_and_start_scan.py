#!/usr/bin/env -S uv run
"""Start a Greenbone Full and fast task for one TCP port on 192.168.20.58."""

import argparse
import json
import os
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path
from xml.sax.saxutils import escape

from dotenv import load_dotenv

TARGET_IP = "192.168.20.58"
SCAN_CONFIG = "Full and fast"

WAIT_FOR_PORT = """
import socket
import sys
import time

address = (sys.argv[1], int(sys.argv[2]))
deadline = time.monotonic() + 60
while True:
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        sys.exit(f"TCP port {address[0]}:{address[1]} did not become reachable within 60 seconds")
    try:
        with socket.create_connection(address, timeout=min(3, remaining)):
            break
    except OSError:
        time.sleep(min(1, max(0, deadline - time.monotonic())))
"""


GMP_CLIENT = """
import json
import socket
import sys
import xml.etree.ElementTree as ET

commands = json.load(sys.stdin)
with socket.socket(socket.AF_UNIX) as connection:
    connection.settimeout(30)
    connection.connect('/run/gvmd/gvmd.sock')
    for command in commands:
        connection.sendall(command.encode())
        parser = ET.XMLPullParser(events=('start', 'end'))
        depth = 0
        while True:
            data = connection.recv(65536)
            if not data:
                sys.exit('Greenbone closed the GMP connection')
            parser.feed(data)
            response = None
            for event, element in parser.read_events():
                depth += 1 if event == 'start' else -1
                if depth == 0:
                    response = element
            if response is not None:
                break
        if not response.attrib['status'].startswith('2'):
            sys.exit(response.attrib['status_text'])
    print(ET.tostring(response, encoding='unicode'))
"""


def gmp_request(manager, username, password, command):
    auth = ET.Element("authenticate")
    credentials = ET.SubElement(auth, "credentials")
    ET.SubElement(credentials, "username").text = username
    ET.SubElement(credentials, "password").text = password
    auth_xml = ET.tostring(auth, encoding="unicode")

    response = subprocess.check_output(
        ["docker", "exec", "-i", manager, "python3", "-c", GMP_CLIENT],
        input=json.dumps([auth_xml, command]),
        text=True,
    )
    return ET.fromstring(response)


def scan(
    port, username, password, manager, scanner, *, task_name=None, report_id_only=False
):
    progress = sys.stderr if report_id_only else sys.stdout

    def gmp(command):
        return gmp_request(manager, username, password, command)

    configs = gmp('<get_configs filter="rows=-1"/>')
    config_id = next(
        (
            config.attrib["id"]
            for config in configs.findall("config")
            if config.findtext("name") == SCAN_CONFIG
        ),
        None,
    )
    if config_id is None:
        raise RuntimeError(
            f"Greenbone's {SCAN_CONFIG} scan configuration is unavailable"
        )

    # The service can still be starting after Docker returns from restart.
    try:
        subprocess.run(
            [
                "docker",
                "exec",
                scanner,
                "python3",
                "-c",
                WAIT_FOR_PORT,
                TARGET_IP,
                str(port),
            ],
            check=True,
            timeout=65,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        raise RuntimeError(
            f"The scanner could not reach {TARGET_IP}:{port} during the readiness check."
        ) from error

    scanners = gmp('<get_scanners filter="name=OpenVAS Default"/>')
    scanner_id = next(
        (
            item.attrib["id"]
            for item in scanners.findall("scanner")
            if item.findtext("host") == "/run/ospd/ospd-openvas.sock"
        ),
        None,
    )
    if scanner_id is None:
        raise RuntimeError("Greenbone's local OSP scanner is unavailable")
    label = f"{TARGET_IP}:{port} ({uuid.uuid4().hex[:8]})"
    ports = gmp(
        f"<create_port_list><name>{label}</name>"
        f"<port_range>T:{port}</port_range></create_port_list>"
    ).attrib["id"]
    target = gmp(
        f"<create_target><name>{label}</name><hosts>{TARGET_IP}</hosts>"
        f'<port_list id="{ports}"/><alive_tests>Consider Alive</alive_tests>'
        "</create_target>"
    ).attrib["id"]
    task = gmp(
        f'<create_task><name>{escape(task_name or label)}</name><target id="{target}"/>'
        f'<config id="{config_id}"/><scanner id="{scanner_id}"/></create_task>'
    ).attrib["id"]
    print(f"Task ID {task}", file=progress, flush=True)
    report = gmp(f'<start_task task_id="{task}"/>').findtext("report_id")
    print(f"Report ID {report}", file=progress, flush=True)
    try:
        while True:
            status = gmp(f'<get_tasks task_id="{task}"/>').findtext("task/status")
            if status in {"Done", "Stopped", "Interrupted", "Internal Error"}:
                print(f"Task status {status}", file=progress, flush=True)
                if status == "Done" and report_id_only and report:
                    print(report)
                return 0 if status == "Done" else 1
            time.sleep(5)
    except KeyboardInterrupt, RuntimeError, OSError, subprocess.CalledProcessError:
        gmp(f'<stop_task task_id="{task}"/>')
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("port", type=int, metavar="PORT")
    parser.add_argument("--task-name", help="Name of the Greenbone scan task")
    parser.add_argument(
        "--report-id-only",
        action="store_true",
        help="Print only the completed report ID to stdout and send progress to stderr",
    )
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("PORT must be between 1 and 65535")
    load_dotenv(Path(__file__).resolve().parents[2] / ".env", interpolate=False)
    username = os.environ.get("GMP_USERNAME", "admin")
    password = os.environ.get("GMP_PASSWORD")
    if not password:
        parser.error("Set GMP_PASSWORD in the project .env file or environment")
    try:
        return scan(
            args.port,
            username,
            password,
            os.environ.get("GVMD_CONTAINER", "greenbone-community-edition-gvmd-1"),
            os.environ.get(
                "OPENVAS_CONTAINER", "greenbone-community-edition-ospd-openvas-1"
            ),
            task_name=args.task_name,
            report_id_only=args.report_id_only,
        )
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"OpenVAS task failed: {error}\n")
    except KeyboardInterrupt:
        parser.exit(130, "OpenVAS task interrupted\n")


if __name__ == "__main__":
    raise SystemExit(main())
