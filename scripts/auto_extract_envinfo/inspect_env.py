#!/usr/bin/env python3
"""Inspect the Docker environment behind an OpenVAS finding.

Usage:
    ./inspect_env.py <target-dir>
    ./inspect_env.py <target-dir>/report.csv

<target-dir> must contain:
    environment/                 a Docker Compose project
    report.csv                   the OpenVAS CSV report

The stack is built and started with a project name derived from the target path,
so targets whose compose directory is also named "environment" do not collide.
It is left running. The report's port is mapped to the publishing container and
that container is inspected; the resulting JSON goes to stdout. Progress and
warnings go to stderr.

Only the Python standard library is used.
"""

import csv
import hashlib
import html
import json
import os
import re
import subprocess
import sys
import time
from urllib.parse import urlsplit

TOOL_CANDIDATES = [
    "sh", "bash", "dash", "sed", "grep", "egrep", "awk", "find", "xargs",
    "cat", "ls", "cp", "mv", "rm", "mkdir", "touch", "chmod", "chown",
    "chattr", "readlink", "realpath", "tr", "cut", "head", "tail", "sort",
    "uniq", "base64", "od", "tar", "gzip", "file", "strings", "jq",
    "curl", "wget", "nc", "socat", "ss", "netstat", "lsof", "ps", "pkill",
    "killall", "ip", "ifconfig", "route", "iptables", "nft", "setcap",
    "getcap", "capsh", "openssl", "python", "python3", "perl", "ruby", "node",
    "php", "java", "javac", "dpkg", "dpkg-query", "apt", "apt-get", "apk",
    "rpm", "dnf", "yum", "zypper", "systemctl", "service", "supervisord",
    "runit", "s6-svscan", "crontab", "cron", "mount", "findmnt", "uname",
    "hostname", "getent", "nslookup", "dig", "ping", "mysql", "psql",
    "redis-cli", "mongosh", "mongo", "sqlite3",
]

WEB_SERVERS = {
    "apache2", "httpd", "nginx", "openresty", "lighttpd", "caddy",
    "php-fpm", "php-fpm7.4", "php-fpm8.1", "jetty", "tomcat",
}
INTERPRETERS = {
    "sh", "bash", "dash", "java", "python", "python3", "node", "nodejs",
    "perl", "ruby", "php", "su", "tini", "dumb-init",
}
HOME_APP_NAMES = {
    "catalina": "tomcat",
    "activemq": "activemq",
    "jetty": "jetty",
    "coldfusion": "coldfusion",
    "es": "elasticsearch",
}
VERSION_ARGS = {
    "etcd": ["--version"],
    "redis": ["--version"],
    "nginx": ["-v"],
    "apache2": ["-v"],
    "httpd": ["-v"],
    "mysqld": ["--version"],
    "mysql": ["--version"],
    "postgres": ["--version"],
    "php": ["-v"],
}
GENERIC_TITLE_PARTS = {
    "login", "log in", "sign in", "welcome", "welcome to", "home",
    "dashboard", "index", "untitled", "default", "administrator",
    "administration", "admin", "console", "management console",
}

# Docker's default capability set, as bit numbers.
DEFAULT_CAP_BITS = {0, 1, 3, 4, 5, 6, 7, 8, 10, 13, 18, 27, 29, 31}
CAP_NAMES = [
    "CHOWN", "DAC_OVERRIDE", "DAC_READ_SEARCH", "FOWNER", "FSETID", "KILL",
    "SETGID", "SETUID", "SETPCAP", "LINUX_IMMUTABLE", "NET_BIND_SERVICE",
    "NET_BROADCAST", "NET_ADMIN", "NET_RAW", "IPC_LOCK", "IPC_OWNER",
    "SYS_MODULE", "SYS_RAWIO", "SYS_CHROOT", "SYS_PTRACE", "SYS_PACCT",
    "SYS_ADMIN", "SYS_BOOT", "SYS_NICE", "SYS_RESOURCE", "SYS_TIME",
    "SYS_TTY_CONFIG", "MKNOD", "LEASE", "AUDIT_WRITE", "AUDIT_CONTROL",
    "SETFCAP", "MAC_OVERRIDE", "MAC_ADMIN", "SYSLOG", "WAKE_ALARM",
    "BLOCK_SUSPEND", "AUDIT_READ", "PERFMON", "BPF", "CHECKPOINT_RESTORE",
]


# --------------------------------------------------------------------------- #
# subprocess helpers
# --------------------------------------------------------------------------- #

def docker(*args, check=True, input_text=None, timeout=None):
    """Run a docker command and return the completed process."""
    if input_text is not None:
        input_data = input_text.replace("\r\n", "\n").encode("utf-8")
        proc = subprocess.run(
            ["docker", *args],
            input=input_data,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=check,
            timeout=timeout,
        )
        # Decode output to text for caller
        proc.stdout = proc.stdout.decode("utf-8", errors="replace")
        proc.stderr = proc.stderr.decode("utf-8", errors="replace")
        return proc

    return subprocess.run(
        ["docker", *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=check,
        timeout=timeout,
    )


def exec_ok(cid, args, timeout=15):
    """Run a command in the container; return stdout, or '' on failure."""
    try:
        p = docker("exec", cid, *args, check=False, timeout=timeout)
    except (subprocess.SubprocessError, OSError):
        return ""
    return p.stdout.strip() if p.returncode == 0 else ""


def read_file(cid, path, limit=65536):
    out = exec_ok(cid, ["cat", path])
    return out[:limit]


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


# --------------------------------------------------------------------------- #
# report and compose
# --------------------------------------------------------------------------- #

def find_report(root):
    report = os.path.join(root, "report.csv")
    if not os.path.isfile(report):
        fail(f"no report.csv in {root}")
    return report


def report_ports(report):
    """Unique (port, protocol) candidates, most severe first."""
    with open(report, newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))

    seen = {}
    for order, row in enumerate(rows):
        raw = (row.get("Port") or "").strip()
        if not raw.isdigit():
            continue
        key = (int(raw), ((row.get("Port Protocol") or "tcp").strip().lower() or "tcp"))
        try:
            cvss = float(row.get("CVSS") or 0)
        except ValueError:
            cvss = 0.0
        if key not in seen:
            seen[key] = {"port": key[0], "protocol": key[1], "cvss": cvss, "order": order}
        else:
            seen[key]["cvss"] = max(seen[key]["cvss"], cvss)

    if not seen:
        # Fallback: check compose file for published ports if report has no port
        compose_file = os.path.join(os.path.dirname(report), "environment", "docker-compose.yml")
        if not os.path.isfile(compose_file):
            compose_file = os.path.join(os.path.dirname(report), "environment", "docker-compose.yaml")
        if os.path.isfile(compose_file):
            try:
                with open(compose_file, "r", encoding="utf-8") as f:
                    comp_text = f.read()
                matches = re.findall(r'["\']?(\d+):(\d+)["\']?', comp_text)
                for host_p, cont_p in matches:
                    seen[(int(host_p), "tcp")] = {"port": int(host_p), "protocol": "tcp", "cvss": 0.0, "order": 0}
            except Exception:
                pass
    if not seen:
        fail(f"report has no usable Port column values: {report}")
    return sorted(seen.values(), key=lambda item: (-item["cvss"], item["order"]))


def project_name(env_dir):
    digest = hashlib.sha1(os.path.realpath(env_dir).encode()).hexdigest()[:12]
    return f"env-inspect-{digest}"


def compose_up(env_dir, project):
    print(f"building and starting {env_dir} (project {project})", file=sys.stderr)
    try:
        result = subprocess.run(
            ["docker", "compose", "-p", project, "up", "-d", "--build"],
            cwd=env_dir,
            stdout=sys.stderr,
            stderr=sys.stderr,
        )
    except OSError as err:
        fail(f"cannot run docker compose: {err}")
    if result.returncode != 0:
        fail(f"docker compose up failed in {env_dir}")


def project_containers(project):
    out = docker(
        "ps", "-q", "--filter", f"label=com.docker.compose.project={project}"
    ).stdout.split()
    containers = []
    for cid in out:
        containers.extend(json.loads(docker("inspect", cid).stdout))
    return containers


def map_port(containers, candidates):
    """Return (candidate, container info, internal port) for the best mapping."""
    for candidate in candidates:
        for info in containers:
            state = info.get("State") or {}
            if not state.get("Running"):
                continue
            ports = (info.get("NetworkSettings") or {}).get("Ports") or {}
            for key, bindings in ports.items():
                try:
                    internal, protocol = key.split("/", 1)
                except ValueError:
                    continue
                if protocol != candidate["protocol"]:
                    continue
                for binding in bindings or []:
                    if str(binding.get("HostPort")) == str(candidate["port"]):
                        return candidate, info, int(internal)
    return None


def published_ports(containers):
    summary = []
    for info in containers:
        ports = (info.get("NetworkSettings") or {}).get("Ports") or {}
        for key, bindings in ports.items():
            for binding in bindings or []:
                summary.append(f"{binding.get('HostPort')}->{key}")
    return ", ".join(sorted(set(summary))) or "none"


# --------------------------------------------------------------------------- #
# in-container probes
# --------------------------------------------------------------------------- #

PROBE = r"""
PORT="$1"
PROTO="$2"

printf '@@id\n'
id 2>/dev/null || true

printf '@@os\n'
[ -r /etc/os-release ] && cat /etc/os-release
[ -r /etc/issue ] && { printf 'ISSUE='; head -n 1 /etc/issue; }

printf '@@tools\n'
for t in __TOOLS__; do
    command -v "$t" >/dev/null 2>&1 && printf '%s\n' "$t"
done

printf '@@listen\n'
for f in /proc/net/tcp /proc/net/tcp6 /proc/net/udp /proc/net/udp6; do
    [ -r "$f" ] || continue
    case "$f" in
        *udp*) want=07 ;;
        *)     want=0A ;;
    esac
    while read -r sl local rem st txq tr retr uid timeout inode rest; do
        [ "$st" = "$want" ] || continue
        printf 'L %s %s %s\n' "${f##*/}" "$local" "$inode"
    done < "$f"
done

printf '@@sockets\n'
for fd in /proc/[0-9]*/fd/*; do
    target=$(readlink "$fd" 2>/dev/null) || continue
    case "$target" in
        socket:*)
            inode=${target#socket:}
            inode=${inode#\[}
            inode=${inode%\]}
            printf 'F %s %s\n' "$fd" "$inode"
            ;;
    esac
done

printf '@@procs\n'
for p in /proc/[0-9]*; do
    [ -r "$p/cmdline" ] || continue
    cmd=$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null)
    [ -n "$cmd" ] || continue
    exe=$(readlink "$p/exe" 2>/dev/null)
    cwd=$(readlink "$p/cwd" 2>/dev/null)
    printf 'P %s\037%s\037%s\037%s\n' "${p#/proc/}" "$exe" "$cwd" "$cmd"
done

printf '@@mountinfo\n'
cat /proc/self/mountinfo 2>/dev/null || true

printf '@@caps\n'
while read -r key value rest; do
    case "$key" in
        CapEff:|CapBnd:) printf '%s %s\n' "${key%:}" "$value" ;;
    esac
done < /proc/1/status

printf '@@init\n'
[ -e /sbin/init ] && printf 'sbin_init\n'
[ -d /run/systemd/system ] && printf 'systemd\n'

printf '@@repo\n'
for f in /etc/apt/sources.list /etc/apk/repositories; do
    [ -r "$f" ] && { printf 'FILE %s\n' "$f"; cat "$f"; }
done
for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources /etc/yum.repos.d/*.repo /etc/zypp/repos.d/*.repo; do
    [ -r "$f" ] && { printf 'FILE %s\n' "$f"; cat "$f"; }
done

printf '@@env\n'
tr '\0' '\n' < /proc/1/environ 2>/dev/null |
    grep -E '^(HOME|PWD|PATH|JAVA_HOME|CATALINA_HOME|PHP_INI_DIR|[A-Za-z0-9_]+_HOME)=' 2>/dev/null || true
""".replace("__TOOLS__", " ".join(TOOL_CANDIDATES))

PATH_PROBE = r"""
command -v rm >/dev/null 2>&1 || exit 0
for path in "$@"; do
    [ -e "$path" ] && printf 'E %s\n' "$path"
    [ -d "$path" ] || continue
    probe="$path/.env-inspect.$$"
    if ( : > "$probe" ) 2>/dev/null; then
        rm -f "$probe" 2>/dev/null
        printf 'W %s\n' "$path"
    fi
done
"""

REPO_PROBE = r"""
for url in "$@"; do
    if command -v curl >/dev/null 2>&1; then
        curl -sS -o /dev/null --max-time 4 "$url" && { printf 'OK\n'; exit 0; }
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 4 --tries=1 -O /dev/null "$url" && { printf 'OK\n'; exit 0; }
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c 'import socket,sys,urllib.parse as p; u=p.urlsplit(sys.argv[1]); socket.create_connection((u.hostname, u.port or (443 if u.scheme == "https" else 80)), 4)' "$url" \
            && { printf 'OK\n'; exit 0; }
    elif command -v nc >/dev/null 2>&1; then
        host=${url#*://}
        host=${host%%/*}
        port=80
        case "$url" in https://*) port=443 ;; esac
        nc -z -w 4 "$host" "$port" && { printf 'OK\n'; exit 0; }
    fi
done
exit 1
"""


def parse_sections(text):
    sections = {}
    current = None
    for line in text.splitlines():
        if line.startswith("@@") and len(line) > 2:
            current = line[2:].strip()
            sections[current] = []
        elif current is not None:
            sections[current].append(line)
    return sections


def probe_container(cid, port, protocol):
    p = docker(
        "exec", "-i", cid, "sh", "-s", str(port), protocol,
        check=False, timeout=60, input_text=PROBE,
    )
    if p.returncode != 0 and not p.stdout:
        fail(f"in-container probe failed: {p.stderr.strip() or p.returncode}")
    return parse_sections(p.stdout)


def wait_for_port(cid, port, protocol, timeout=120):
    """Poll /proc/net for a listening socket on port. Return True on success."""
    if protocol == "udp":
        files, state = "/proc/net/udp /proc/net/udp6", "07"
    else:
        files, state = "/proc/net/tcp /proc/net/tcp6", "0A"
    script = (
        f'for f in {files}; do [ -r "$f" ] || continue; '
        f'while read -r sl local rem st rest; do '
        f'[ "$st" = "{state}" ] || continue; '
        f'[ "${{local##*:}}" = "{port:04X}" ] && exit 0; '
        f'done < "$f"; done; exit 1'
    )
    deadline = time.monotonic() + timeout
    while True:
        if docker("exec", cid, "sh", "-c", script, check=False).returncode == 0:
            return True
        if time.monotonic() > deadline:
            return False
        time.sleep(1.5)


def probe_paths(cid, paths):
    paths = [p for p in dict.fromkeys(paths) if p]
    if not paths:
        return set(), set()
    p = docker(
        "exec", "-i", cid, "sh", "-s", "--", *paths,
        check=False, timeout=60, input_text=PATH_PROBE,
    )
    existing, writable = set(), set()
    for line in p.stdout.splitlines():
        if line.startswith("E "):
            existing.add(line[2:])
        elif line.startswith("W "):
            writable.add(line[2:])
    return existing, writable


def http_fingerprint(cid, port, protocol, tools):
    if protocol != "tcp" or not ({"curl", "wget"} & set(tools)):
        return {}

    schemes = ["https"] if port in (443, 8443, 9443, 4443) else ["http", "https"]
    text = ""
    for scheme in schemes:
        if "curl" in tools:
            args = [
                "curl", "-sS", "-i", "-k", "--max-time", "3",
                "--max-filesize", "131072", f"{scheme}://127.0.0.1:{port}/",
            ]
        else:
            args = [
                "wget", "-q", "-S", "-O", "-", "--timeout=3", "--tries=1",
                f"{scheme}://127.0.0.1:{port}/",
            ]
        try:
            p = docker("exec", cid, *args, check=False, timeout=10)
        except (subprocess.SubprocessError, OSError):
            continue
        if "curl" in tools:
            candidate = (p.stdout or "") + (p.stderr or "")
        else:
            candidate = (p.stderr or "") + (p.stdout or "")
        if "HTTP/" in candidate:
            text = candidate
            break
        text = text or candidate
    if "HTTP/" not in text:
        return {}

    lines = text.replace("\r\n", "\n").splitlines()
    status = lines[0].strip()
    headers = {}
    for line in lines[1:]:
        if not line.strip():
            break
        if ":" in line:
            key, value = line.split(":", 1)
            headers[key.strip().lower()] = value.strip()
    body = text.split("\n\n", 1)[1] if "\n\n" in text else ""

    title = ""
    match = re.search(r"<title[^>]*>(.*?)</title>", body, re.I | re.S)
    if match:
        title = html.unescape(re.sub(r"\s+", " ", match.group(1))).strip()

    app = clean_title(title)
    version = ""

    # Elasticsearch answers with JSON, not HTML; lucene_version must not win.
    if "lucene_version" in body or "You Know, for Search" in body:
        app = "elasticsearch"
        match = re.search(r'"number"\s*:\s*"([0-9][^"]*)"', body)
        if match:
            version = match.group(1)

    if not version:
        for pattern in (
            r'version\s*[=:"\'\s]+v?(\d+(?:\.\d+){1,3})',
            r'/(\d+(?:\.\d+){1,3})\b',
        ):
            match = re.search(pattern, body, re.I)
            if match:
                version = match.group(1)
                break

    server_name = clean_server(headers.get("server", ""))
    if not app:
        app = server_name
    if not version and app and app == server_name:
        match = re.search(r"/(\d+(?:\.\d+){1,3})", headers.get("server", ""))
        if match:
            version = match.group(1)

    return {
        "status": status,
        "server": headers.get("server", ""),
        "title": title,
        "application": app,
        "version": version,
    }


def clean_title(title):
    text = re.sub(r"\s+", " ", title or "").strip()
    bracket = re.search(r"\[([A-Za-z][\w .-]*)\]", text)
    if bracket:
        outside = re.sub(r"\[[^\]]*\]", "", text).strip().lower()
        if outside in GENERIC_TITLE_PARTS or outside == "dashboard":
            text = bracket.group(1)
    if "default page" in text.lower() or text.lower() in GENERIC_TITLE_PARTS:
        return ""
    parts = [p.strip() for p in re.split(r"\s+[-–—|:]\s+", text) if p.strip()]
    parts = [p for p in parts if p.lower() not in GENERIC_TITLE_PARTS]
    name = parts[-1] if parts else text
    name = re.sub(r"^(Apache|Welcome to|Login to|Login|Sign in)\s+", "", name, flags=re.I)
    name = re.sub(r"/v?\d+(?:\.\d+)+.*$", "", name)
    name = re.sub(r"\s+(Administrator|Admin|Console|Login|Home)$", "", name, flags=re.I)
    name = name.strip(" !")
    if not name or len(name.split()) > 2:
        return ""
    return name.lower().replace(" ", "-")


def clean_server(server):
    parts = (server or "").split()
    if not parts:
        return ""
    name = re.split(r"[/ (]", parts[0], maxsplit=1)[0].strip().lower()
    if name in {"apache", "apache2"}:
        return "apache2"
    return name if re.fullmatch(r"[a-z][a-z0-9.+_-]*", name) else ""


# --------------------------------------------------------------------------- #
# inference
# --------------------------------------------------------------------------- #

def parse_probe(sections):
    facts = {}
    facts["os_release"] = {}
    for line in sections.get("os", []):
        if "=" in line:
            key, value = line.split("=", 1)
            facts["os_release"][key.strip()] = value.strip().strip('"')
        elif line.startswith("ISSUE="):
            facts["issue"] = line[6:].strip()
    facts["tools"] = sorted({
        line.strip() for line in sections.get("tools", []) if line.strip()
    })
    facts["id"] = " ".join(sections.get("id", [])).strip()

    facts["listeners"] = []
    for line in sections.get("listen", []):
        parts = line.split()
        if len(parts) >= 4 and parts[0] == "L":
            _, proto, local, inode = parts[:4]
            try:
                port = int(local.rsplit(":", 1)[1], 16)
            except (ValueError, IndexError):
                continue
            facts["listeners"].append({
                "proto": proto, "port": port, "inode": inode,
            })

    facts["socket_owner"] = {}
    for line in sections.get("sockets", []):
        parts = line.split()
        if len(parts) >= 3 and parts[0] == "F":
            match = re.match(r"/proc/(\d+)/fd/", parts[1])
            if match:
                facts["socket_owner"].setdefault(parts[2], set()).add(int(match.group(1)))

    facts["procs"] = {}
    for line in sections.get("procs", []):
        if not line.startswith("P "):
            continue
        fields = line[2:].split("\x1f", 3)
        if len(fields) != 4:
            continue
        try:
            pid = int(fields[0])
        except ValueError:
            continue
        facts["procs"][pid] = {
            "exe": fields[1], "cwd": fields[2], "cmd": fields[3],
        }

    facts["mountinfo"] = []
    for line in sections.get("mountinfo", []):
        fields = line.split()
        if len(fields) < 7 or "-" not in fields:
            continue
        sep = fields.index("-")
        if len(fields) <= sep + 1:
            continue
        facts["mountinfo"].append({
            "point": fields[4].replace("\\040", " "),
            "options": fields[5],
            "fstype": fields[sep + 1],
        })

    facts["caps"] = {}
    for line in sections.get("caps", []):
        parts = line.split()
        if len(parts) == 2:
            facts["caps"][parts[0]] = parts[1]
    facts["init_flags"] = set(sections.get("init", []))
    facts["repo_text"] = "\n".join(sections.get("repo", []))
    facts["env"] = {}
    for line in sections.get("env", []):
        if "=" in line:
            key, value = line.split("=", 1)
            facts["env"][key] = value
    return facts


def process_app(facts, owner_pids):
    """Return (application, install_root, app_exe) from the port owner process."""
    info = None
    for pid in sorted(owner_pids):
        if pid in facts["procs"]:
            info = facts["procs"][pid]
            break
    if info is None and 1 in facts["procs"]:
        info = facts["procs"][1]

    if not info:
        return "unknown", "", ""

    cmd = info["cmd"]
    tokens = cmd.split()
    homes = {}
    for token in tokens:
        match = re.match(r"-D([A-Za-z0-9_.-]+)=(\S+)", token)
        if not match:
            continue
        key = match.group(1)
        if key.endswith((".home", ".base", ".root")):
            homes[key.split(".", 1)[0]] = match.group(2)

    app, root, exe = "", "", info.get("exe", "")
    argv0 = os.path.basename(tokens[0]).rstrip(":") if tokens else ""
    for key, value in homes.items():
        if key in {"java", "user"}:
            continue
        app = HOME_APP_NAMES.get(key, key)
        root = value
        break

    if not root:
        for token in tokens:
            match = re.match(r"(/.*)/bin/([A-Za-z0-9_.+-]+)$", token)
            if match:
                root = match.group(1)
                if os.path.basename(root) in {"runtime", "current", "latest"}:
                    root = os.path.dirname(root)
                name = re.sub(r"\.(jar|sh|bin|py|rb|php)$", "", match.group(2))
                if not app:
                    app = name
                break

    exe_name = os.path.basename(exe) if exe else ""
    if exe_name in {"nginx", "openresty"}:
        for index, token in enumerate(tokens):
            if token == "-p" and index + 1 < len(tokens):
                prefix = tokens[index + 1]
                prefix_name = os.path.basename(prefix.rstrip("/"))
                if prefix_name and prefix_name not in {"nginx", "conf", "etc"}:
                    root, app = prefix, prefix_name
                break
    if not app and argv0 and argv0 not in INTERPRETERS:
        app = argv0
    if not app and exe_name and exe_name not in INTERPRETERS:
        app = exe_name

    if not app:
        for token in tokens:
            base = os.path.basename(token)
            match = re.match(r"([A-Za-z][\w.-]*?)[-_]v?(\d+(?:\.\d+)+).*\.jar$", base)
            if match:
                app = match.group(1)
                if not root:
                    root = os.path.dirname(token)
                break

    if not app and info.get("cwd") and info["cwd"] not in {"/", "/root", "/tmp"}:
        app = os.path.basename(info["cwd"])

    if not root and exe_name and exe_name not in INTERPRETERS:
        root = os.path.dirname(exe)
        if os.path.basename(root) in {"bin", "sbin"}:
            root = os.path.dirname(root)

    app = normalize_app(app)
    return app, root, exe


def normalize_app(app):
    name = (app or "").strip().lower()
    name = re.sub(r"\.(jar|sh|bin|py|rb|php)$", "", name)
    # Strip a version suffix only for names where it is not part of the name.
    match = re.match(r"([a-z][a-z-]*?)[-_]?v?\d+(?:\.\d+)*$", name)
    if match and match.group(1) in {
        "coldfusion", "tomcat", "mysql", "php", "jdk", "openjdk",
        "postgres", "postgresql",
    }:
        name = match.group(1)
    aliases = {
        "redis-server": "redis",
        "mysqld": "mysql",
        "httpd": "apache2",
        "java": "",
        "python3": "",
        "python": "",
        "node": "",
        "nodejs": "",
    }
    return aliases.get(name, name)


def binary_version(cid, app, app_exe):
    args = VERSION_ARGS.get(app)
    if not args or not app_exe:
        return ""
    out = exec_ok(cid, [app_exe, *args], timeout=5)
    match = re.search(r"\d+(?:\.\d+){1,3}", out)
    return match.group(0) if match else ""


def app_version(root, package_version, http, manifest_version, real_root=""):
    # A versioned install directory is the most reliable signal; a page's
    # "Version 2.0" is often the web console, not the application.
    for path in (real_root, root):
        if not path:
            continue
        base = os.path.basename(path.rstrip("/"))
        match = re.search(
            r"(?:^|[-_])(v?\d+(?:\.\d+){0,3}(?:[-+][\w.]+)?)$", base
        ) or re.search(
            r"(?<=[a-z])(v?\d+(?:\.\d+){0,3}(?:[-+][\w.]+)?)$", base
        )
        if match:
            return match.group(1).lstrip("v")
    if package_version:
        return package_version
    if http.get("version"):
        return http["version"]
    if manifest_version:
        return manifest_version
    return "unknown"


def package_owner(cid, path, tools):
    """Return (package, version) if path is owned by a distro package."""
    if not path:
        return "", ""
    if "dpkg" in tools:
        out = exec_ok(cid, ["dpkg", "-S", path])
        if out:
            first = out.splitlines()[0]
            package = first.split(":", 1)[0].split(",")[0].strip()
            if package:
                version = exec_ok(cid, ["dpkg-query", "-W", "-f=${Version}", package])
                return package, version
    if "apk" in tools:
        out = exec_ok(cid, ["apk", "info", "-W", path])
        if out and "owned by" in out:
            package = out.rsplit(" ", 1)[-1]
            return package, ""
    if "rpm" in tools:
        out = exec_ok(cid, ["rpm", "-qf", path])
        if out and "not owned" not in out:
            package = out.splitlines()[0].strip()
            version = exec_ok(cid, ["rpm", "-q", "--qf", "%{VERSION}-%{RELEASE}", package])
            return package, version
    return "", ""


def manifest_version(cid, root, existing):
    if not root:
        return "", ""
    package_json = os.path.join(root, "package.json")
    if package_json in existing:
        try:
            data = json.loads(read_file(cid, package_json))
            return data.get("version", ""), data.get("name", "")
        except (ValueError, TypeError):
            pass
    composer_json = os.path.join(root, "composer.json")
    if composer_json in existing:
        try:
            data = json.loads(read_file(cid, composer_json))
            return data.get("version", ""), data.get("name", "")
        except (ValueError, TypeError):
            pass
    for name in ("VERSION", "version.txt", "RELEASE"):
        path = os.path.join(root, name)
        if path in existing:
            text = read_file(cid, path, 1024)
            match = re.search(r"\d+(?:\.\d+){1,3}", text)
            if match:
                return match.group(0), ""
    return "", ""


def apply_package_root(root, method):
    if method == "distro-package" and root.startswith(("/usr/", "/bin/", "/sbin/")):
        return "/usr"
    return root


# --------------------------------------------------------------------------- #
# facts -> JSON
# --------------------------------------------------------------------------- #

def decode_caps(hex_value):
    if not hex_value:
        return ["unknown"]
    try:
        bits = int(hex_value, 16)
    except ValueError:
        return ["unknown"]
    present = {i for i in range(bits.bit_length()) if bits & (1 << i)}
    if present == DEFAULT_CAP_BITS:
        return ["default"]
    names = [CAP_NAMES[i] for i in sorted(present) if i < len(CAP_NAMES)]
    return names or ["none"]


def selected_pids(facts, internal_port):
    inodes = {
        entry["inode"] for entry in facts["listeners"]
        if entry["port"] == internal_port
    }
    pids = set()
    for inode in inodes:
        pids |= facts["socket_owner"].get(inode, set())
    return pids


def build_result(cid, info, candidate, internal_port, facts):
    tools = facts["tools"]
    owner_pids = selected_pids(facts, internal_port)
    proc_app, root, app_exe = process_app(facts, owner_pids)
    http = http_fingerprint(cid, internal_port, candidate["protocol"], tools)

    http_app = http.get("application", "")
    if http_app and (
        not proc_app
        or proc_app in WEB_SERVERS
        or proc_app in INTERPRETERS
        or proc_app.startswith(http_app + "-")
        or http_app.startswith(proc_app + "-")
    ):
        app = http_app
    else:
        app = proc_app or http_app or "unknown"

    # A web app over a generic server lives in a web root, not in the server's package.
    web_candidates = [
        "/var/www/html", "/usr/share/nginx/html", "/app", "/var/www",
        "/srv/www", "/usr/local/www", "/opt/app",
    ]
    path_candidates = list(web_candidates)
    if root:
        path_candidates.append(root)
    config_candidates = config_paths_for(app, proc_app, root, facts, owner_pids)
    mount_destinations = [
        mount.get("Destination", "") for mount in (info.get("Mounts") or [])
        if mount.get("Destination")
    ]
    config_mounts = [
        path for path in mount_destinations
        if re.search(r"\.(conf|cfg|ya?ml|json|xml|properties|ini|toml)$", path)
        or path.startswith("/etc/") or "/conf/" in path or path.endswith("/conf")
    ]
    config_candidates += config_mounts
    path_candidates += config_candidates + mount_destinations
    marker_candidates = []
    if root:
        marker_candidates = [
            os.path.join(root, name) for name in (
                "package.json", "composer.json", "requirements.txt",
                "pyproject.toml", "VERSION", "version.txt", "RELEASE",
                "node_modules", "vendor", "Gemfile", "Gemfile.lock",
            )
        ]
    exe_dir = os.path.dirname(app_exe) if app_exe else ""
    cwd = facts["procs"].get(next(iter(owner_pids), 0), {}).get("cwd", "")
    writable_candidates = [
        root, exe_dir, cwd if cwd != "/" else "", *config_candidates,
        *mount_destinations,
        "/etc", "/usr", "/usr/local", "/usr/lib", "/usr/bin", "/opt",
        "/var", "/var/www", "/var/lib", "/srv", "/home", "/root",
        "/tmp", "/run", "/dev/shm",
    ]
    existing, writable = probe_paths(
        cid, path_candidates + marker_candidates + writable_candidates + ["/tmp", "/run"]
    )

    real_root = ""
    if root and "realpath" in tools:
        resolved = exec_ok(cid, ["realpath", root])
        if resolved.startswith("/"):
            real_root = resolved

    manifest_ver, manifest_name = manifest_version(cid, root, existing)
    if app == "unknown" and manifest_name:
        app = normalize_app(manifest_name)

    web_root = next((p for p in web_candidates if p in existing), "")
    if http_app and (proc_app in WEB_SERVERS or proc_app in INTERPRETERS):
        if web_root:
            root = web_root

    package, package_version = ("", "")
    if app == proc_app and app_exe and os.path.basename(app_exe) not in INTERPRETERS:
        exe_base = os.path.basename(app_exe)
        server_binary = exe_base in WEB_SERVERS or exe_base.startswith(
            ("nginx", "openresty", "httpd", "apache2", "php-fpm")
        )
        if not server_binary or app in WEB_SERVERS:
            package, package_version = package_owner(cid, app_exe, tools)
    method = install_method(app, proc_app, root, app_exe, package, existing)
    root = apply_package_root(root, method) if root else root

    config_paths = [p for p in config_candidates if p in existing]
    config_paths = list(dict.fromkeys(config_paths))[:8]

    version = clean_version(app_version(root, package_version, http, manifest_ver, real_root))
    if version == "unknown":
        version = binary_version(cid, app, app_exe)
    if version == "unknown" and http.get("server") and app in WEB_SERVERS:
        match = re.search(r"/(\d+(?:\.\d+){1,3})", http["server"])
        if match:
            version = match.group(1)

    # OS
    release = facts["os_release"]
    distro = release.get("ID") or (release.get("NAME") or "unknown").split()[0].lower()
    release_version = release.get("VERSION_ID") or release.get("VERSION") or "unknown"
    package_manager = detect_pm(tools)
    repo_roots = repo_urls(facts["repo_text"])
    reachable = repos_reachable(cid, repo_roots, tools) if package_manager != "none" else "unknown"

    # Filesystem
    uid = ""
    match = re.search(r"uid=(\d+)", facts["id"])
    if match:
        uid = match.group(1)
    exec_user = "root" if uid == "0" else (uid or "unknown")

    mounts = []
    for mount in info.get("Mounts") or []:
        mounts.append({
            "type": mount.get("Type", ""),
            "source": mount.get("Source", ""),
            "destination": mount.get("Destination", ""),
            "rw": bool(mount.get("RW", True)),
        })

    volatile = set()
    for mount in facts["mountinfo"]:
        point = mount["point"]
        if mount["fstype"] != "tmpfs":
            continue
        if point in {"/dev", "/dev/pts", "/dev/mqueue"}:
            continue
        if point == "/proc" or point.startswith("/proc/"):
            continue
        if point == "/sys" or point.startswith("/sys/"):
            continue
        volatile.add(point)
    for key in ((info.get("HostConfig") or {}).get("Tmpfs") or {}):
        volatile.add(key)
    if "/tmp" in existing:
        volatile.add("/tmp")
    if "/run" in existing:
        volatile.add("/run")

    init_names = {"systemd", "init"}
    pid1 = facts["procs"].get(1, {})
    pid1_name = os.path.basename((pid1.get("exe") or "").split()[0]) if pid1.get("exe") else ""
    init_system = pid1_name in init_names or "systemd" in facts["init_flags"]

    main_pid_is_1 = (1 in owner_pids) if owner_pids else "unknown"
    applies_on_restart = True

    return {
        "service": {
            "port_internal": internal_port,
            "protocol": candidate["protocol"],
            "application": app or "unknown",
            "version": version,
            "install_method": method,
            "install_root": root or "unknown",
            "config_paths": config_paths,
        },
        "os": {
            "distro": distro,
            "release": release_version,
            "package_manager": package_manager,
            "repos_reachable": reachable,
            "tools": tools,
        },
        "filesystem": {
            "exec_user": exec_user,
            "writable": sorted(writable),
            "mounts": mounts,
            "volatile_paths": sorted(volatile),
            "capabilities": decode_caps(facts["caps"].get("CapEff")),
            "init_system": init_system,
            "read_only_rootfs": bool((info.get("HostConfig") or {}).get("ReadonlyRootfs")),
        },
        "config_lifecycle": {
            "applies_on_restart": applies_on_restart,
            "main_pid_is_1": main_pid_is_1,
        },
    }


def clean_version(version):
    return re.sub(r"^\d+:", "", (version or "").strip())


def config_paths_for(app, proc_app, root, facts, owner_pids):
    paths = []
    tokens = []
    pids = set(owner_pids)
    if 1 in facts["procs"]:
        pids.add(1)
    for pid in pids:
        if pid in facts["procs"]:
            tokens.extend(facts["procs"][pid]["cmd"].split())
    for token in tokens:
        match = re.match(r"-D[\w.]*(?:config|conf)[\w.]*=(\S+)", token)
        if match:
            value = match.group(1)
            if not os.path.isabs(value) and root:
                value = os.path.join(root, value)
            paths.append(value)
        match = re.match(r"--config(?:=|\s+)(\S+)", token)
        if match:
            paths.append(match.group(1))

    if root:
        for name in ("conf", "config", "conf.d", "config.d"):
            paths.append(os.path.join(root, name))
    for name in (app, proc_app):
        if name and name != "unknown":
            paths.extend([
                f"/etc/{name}",
                f"/etc/{name}/{name}.conf",
                f"/etc/{name}.conf",
                f"/usr/local/etc/{name}",
                f"/opt/{name}/conf",
                f"/usr/local/{name}/conf",
            ])
    if proc_app in WEB_SERVERS or app in WEB_SERVERS:
        paths.extend([
            "/etc/apache2", "/etc/apache2/conf-enabled", "/etc/httpd",
            "/etc/nginx", "/usr/local/apache2/conf", "/usr/local/nginx/conf",
        ])
    php_dir = facts["env"].get("PHP_INI_DIR", "")
    if php_dir:
        paths.extend([php_dir, os.path.join(php_dir, "conf.d")])
    return list(dict.fromkeys(p for p in paths if p))


def install_method(app, proc_app, root, app_exe, package, existing):
    if package:
        return "distro-package"
    text = " ".join(filter(None, [root, app_exe]))
    if any(marker in text for marker in (
        "site-packages", "dist-packages", "node_modules", "/vendor/",
        "gems", "composer",
    )):
        return "language-pm"
    if root:
        base = os.path.basename(root.rstrip("/"))
        if re.search(r"[-_]v?\d+(?:\.\d+)+$", base):
            return "tarball"
        if root == "/opt" or root.startswith("/opt/"):
            return "tarball"
        if root == "/usr/local" or root.startswith("/usr/local/"):
            return "tarball"
    if any(path.endswith(("/node_modules", "/vendor", "/.venv")) for path in existing):
        return "language-pm"
    return "image"


def detect_pm(tools):
    if "apt-get" in tools or "apt" in tools or "dpkg" in tools:
        return "apt"
    if "apk" in tools:
        return "apk"
    if "dnf" in tools or "yum" in tools or "rpm" in tools:
        return "dnf"
    if "zypper" in tools:
        return "zypper"
    return "none"


def repo_urls(text):
    roots = []
    for url in re.findall(r"https?://[^\s\"'#]+", text):
        try:
            parts = urlsplit(url)
        except ValueError:
            continue
        if parts.scheme and parts.netloc:
            root = f"{parts.scheme}://{parts.netloc}/"
            if root not in roots:
                roots.append(root)
    return roots[:3]


def repos_reachable(cid, urls, tools):
    if not urls:
        return "unknown"
    if not ({"curl", "wget", "python3", "nc"} & set(tools)):
        return "unknown"
    p = docker(
        "exec", "-i", cid, "sh", "-s", "--", *urls,
        check=False, timeout=20, input_text=REPO_PROBE,
    )
    if p.returncode == 0 and "OK" in p.stdout:
        return True
    return False


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #

def main(argv):
    if len(argv) != 2:
        print(f"usage: {os.path.basename(argv[0])} <target-dir>", file=sys.stderr)
        return 2

    target = os.path.abspath(argv[1])
    report = None
    if os.path.isfile(target):
        if target.endswith(".csv"):
            report = target
            target = os.path.dirname(target)
        else:
            fail(f"expected a target directory or its report CSV: {target}")

    env_dir = os.path.join(target, "environment")
    if not os.path.isdir(env_dir):
        # Also accept the environment directory itself.
        if os.path.isdir(target) and any(
            os.path.isfile(os.path.join(target, name))
            for name in ("docker-compose.yml", "docker-compose.yaml",
                         "compose.yml", "compose.yaml")
        ):
            env_dir = target
            target = os.path.dirname(target)
        else:
            fail(f"no environment/ Docker Compose project in {target}")

    report = report or find_report(target)
    candidates = report_ports(report)
    project = project_name(env_dir)

    compose_up(env_dir, project)
    containers = project_containers(project)
    if not containers:
        fail(f"no containers found for compose project {project}")

    mapped = map_port(containers, candidates)
    if not mapped:
        fail(
            "no running container publishes report port(s) "
            f"{[(c['port'], c['protocol']) for c in candidates]}; "
            f"published ports: {published_ports(containers)}"
        )
    candidate, info, internal_port = mapped
    cid = info["Id"]
    name = info.get("Name", "").lstrip("/") or cid[:12]

    if len(candidates) > 1:
        others = [c for c in candidates if c is not candidate]
        print(
            "note: multiple report ports; inspecting "
            f"{candidate['port']}/{candidate['protocol']} (highest CVSS first), "
            f"ignored {[(c['port'], c['protocol']) for c in others]}",
            file=sys.stderr,
        )
    print(
        f"report {os.path.basename(report)}: host port {candidate['port']}/"
        f"{candidate['protocol']} -> container port {internal_port} "
        f"on {name}",
        file=sys.stderr,
    )

    if not wait_for_port(cid, internal_port, candidate["protocol"]):
        print(
            f"warning: {internal_port}/{candidate['protocol']} is not listening after 120s",
            file=sys.stderr,
        )

    sections = probe_container(cid, internal_port, candidate["protocol"])
    facts = parse_probe(sections)
    result = build_result(cid, info, candidate, internal_port, facts)
    json.dump(result, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
