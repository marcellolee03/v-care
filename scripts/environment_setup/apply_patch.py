import argparse
import json
import subprocess
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run a patch as root in the container publishing a host port, then restart it."
    )
    parser.add_argument("port", type=int, help="Published host port")
    parser.add_argument(
        "script", type=Path, help="Local script with a shebang for its interpreter"
    )
    args = parser.parse_args()

    if not 1 <= args.port <= 65535:
        parser.error("port must be from 1 to 65535")
    if not args.script.is_file():
        parser.error(f"script file does not exist: {args.script}")
    script = args.script.resolve()

    try:
        running = subprocess.check_output(["docker", "ps", "-q"], text=True).split()
        if not running:
            parser.exit(1, "no running Docker containers\n")

        mappings = subprocess.check_output(
            [
                "docker",
                "inspect",
                "--type",
                "container",
                "--format",
                "{{.Id}} {{json .NetworkSettings.Ports}}",
                *running,
            ],
            text=True,
        )
        matches = []
        for line in mappings.splitlines():
            container, ports = line.split(" ", 1)
            if any(
                binding["HostPort"] == str(args.port)
                for bindings in (json.loads(ports) or {}).values()
                for binding in bindings or []
            ):
                matches.append(container)
        if not matches:
            parser.exit(1, f"no running container publishes host port {args.port}\n")
        if len(matches) > 1:
            parser.exit(1, f"multiple containers publish host port {args.port}\n")

        container = matches[0]
        docker_exec = ["docker", "exec", "--user", "0", container]
        directory = subprocess.check_output(
            [*docker_exec, "mktemp", "-d", "/tmp/v-care-patch.XXXXXXXXXX"], text=True
        ).strip()
        destination = f"{directory}/{script.name}"
        try:
            subprocess.run(
                ["docker", "cp", str(script), f"{container}:{destination}"], check=True
            )
            subprocess.run([*docker_exec, "chmod", "u+x", destination], check=True)
            subprocess.run([*docker_exec, destination], check=True)
        finally:
            subprocess.run([*docker_exec, "rm", "-rf", "--", directory], check=False)

        subprocess.run(["docker", "restart", container], check=True)
    except subprocess.CalledProcessError as exc:
        return exc.returncode
    except OSError as exc:
        parser.exit(1, f"could not run Docker: {exc}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
