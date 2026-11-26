#!/usr/bin/env -S uv run
"""Start a Greenbone Discovery task for one host-loopback TCP port."""

import argparse
import inspect
import json
import os
import select
import socket
import socketserver
import subprocess
import tempfile
import threading
import time
import uuid
import xml.etree.ElementTree as ET
from contextlib import contextmanager
from pathlib import Path

from dotenv import load_dotenv


# Run the same byte relay at both ends of a private Unix socket.
def relay_bytes(source, destination):
    try:
        while data := source.recv(65536):
            destination.sendall(data)
        destination.shutdown(socket.SHUT_WR)
    except OSError:
        pass


class Relay(socketserver.BaseRequestHandler):
    def handle(self):
        family, address = self.server.upstream
        with socket.socket(family, socket.SOCK_STREAM) as upstream:
            upstream.connect(address)
            outbound = threading.Thread(
                target=relay_bytes, args=(self.request, upstream)
            )
            outbound.start()
            relay_bytes(upstream, self.request)
            outbound.join()


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


def scan(port, username, password, manager, scanner):
    auth = ET.Element("authenticate")
    credentials = ET.SubElement(auth, "credentials")
    ET.SubElement(credentials, "username").text = username
    ET.SubElement(credentials, "password").text = password
    auth_xml = ET.tostring(auth, encoding="unicode")

    def gmp(command):
        response = subprocess.check_output(
            ["docker", "exec", "-i", manager, "python3", "-c", GMP_CLIENT],
            input=json.dumps([auth_xml, command]),
            text=True,
        )
        return ET.fromstring(response)

    configs = gmp('<get_configs filter="name=Discovery"/>')
    config_id = next(
        (
            config.attrib["id"]
            for config in configs.findall("config")
            if config.findtext("name") == "Discovery"
        ),
        None,
    )
    if config_id is None:
        raise RuntimeError("Greenbone's Discovery scan configuration is unavailable")

    # Verify the host endpoint before creating any Greenbone objects.
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=3):
            pass
    except OSError as error:
        raise RuntimeError(f"Cannot reach 127.0.0.1:{port}: {error}") from error

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
    label = f"localhost:{port} ({uuid.uuid4().hex[:8]})"
    with scanner_relay(port, scanner) as relay:
        ports = gmp(
            f"<create_port_list><name>{label}</name>"
            f"<port_range>T:{port}</port_range></create_port_list>"
        ).attrib["id"]
        target = gmp(
            f"<create_target><name>{label}</name><hosts>127.0.0.1</hosts>"
            f'<port_list id="{ports}"/><alive_tests>Consider Alive</alive_tests>'
            "</create_target>"
        ).attrib["id"]
        task = gmp(
            f'<create_task><name>{label}</name><target id="{target}"/>'
            f'<config id="{config_id}"/><scanner id="{scanner_id}"/></create_task>'
        ).attrib["id"]
        print(f"Task ID {task}", flush=True)
        report = gmp(f'<start_task task_id="{task}"/>').findtext("report_id")
        print(f"Report ID {report}", flush=True)
        try:
            while True:
                status = gmp(f'<get_tasks task_id="{task}"/>').findtext("task/status")
                if status in {"Done", "Stopped", "Interrupted", "Internal Error"}:
                    print(f"Task status {status}")
                    return 0 if status == "Done" else 1
                if relay.poll() is not None:
                    raise RuntimeError("The scanner's loopback relay exited")
                time.sleep(5)
        except KeyboardInterrupt, RuntimeError, OSError, subprocess.CalledProcessError:
            gmp(f'<stop_task task_id="{task}"/>')
            raise


@contextmanager
def scanner_relay(port, scanner):
    scanner_image = subprocess.check_output(
        ["docker", "inspect", "--format", "{{.Image}}", scanner], text=True
    ).strip()
    relay_name = f"v-care-openvas-relay-{uuid.uuid4().hex[:12]}"
    relay_code = "\n".join(
        (
            "import socket, socketserver, threading, sys",
            inspect.getsource(relay_bytes),
            inspect.getsource(Relay),
            """
with socketserver.ThreadingTCPServer(('127.0.0.1', int(sys.argv[1])), Relay) as server:
    server.upstream = (socket.AF_UNIX, '/relay/host.sock')
    print('ready', flush=True)
    server.serve_forever()
""",
        )
    )

    with (
        tempfile.TemporaryDirectory(prefix="v-care-openvas-") as directory,
        socketserver.ThreadingUnixStreamServer(
            str(Path(directory) / "host.sock"), Relay
        ) as host_relay,
    ):
        host_relay.daemon_threads = True
        host_relay.upstream = (socket.AF_INET, ("127.0.0.1", port))
        thread = threading.Thread(target=host_relay.serve_forever, daemon=True)
        thread.start()
        try:
            with subprocess.Popen(
                [
                    "docker",
                    "run",
                    "--rm",
                    "--pull",
                    "never",
                    "--name",
                    relay_name,
                    "--network",
                    f"container:{scanner}",
                    "--cap-drop",
                    "ALL",
                    "--security-opt",
                    "no-new-privileges",
                    "--user",
                    f"{os.getuid()}:{os.getgid()}",
                    "-v",
                    f"{directory}:/relay:ro,Z",
                    "--entrypoint",
                    "python3",
                    scanner_image,
                    "-c",
                    relay_code,
                    str(port),
                ],
                stdout=subprocess.PIPE,
                text=True,
            ) as relay:
                try:
                    if (
                        not select.select([relay.stdout], [], [], 20)[0]
                        or relay.stdout.readline().strip() != "ready"
                    ):
                        raise RuntimeError(
                            "Could not start the scanner's loopback relay"
                        )
                    yield relay
                finally:
                    if relay.poll() is None:
                        subprocess.run(
                            ["docker", "stop", "--time", "1", relay_name],
                            stdout=subprocess.DEVNULL,
                            check=False,
                        )
                        relay.terminate()
        finally:
            host_relay.shutdown()
            thread.join()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("port", type=int, metavar="PORT")
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("PORT must be between 1 and 65535")
    load_dotenv(Path(__file__).resolve().parents[1] / ".env", interpolate=False)
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
        )
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"OpenVAS task failed: {error}\n")
    except KeyboardInterrupt:
        parser.exit(130, "OpenVAS task interrupted\n")


if __name__ == "__main__":
    raise SystemExit(main())
