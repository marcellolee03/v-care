from v_care.ai.generator import Generator
from v_care.ai.judge import Judge

details = {"name": "activemq", "source": "vulhub", "nvt_oid": "1.3.6.1.4.1.25623.1.0.108253", "has_oid": True, "has_cve": False, "environment_details": {"service": {"port_internal": 8161, "protocol": "tcp", "application": "activemq", "version": "5.11.1", "install_method": "tarball", "install_root": "/opt/activemq", "config_paths": ["/opt/activemq/conf/login.config", "/opt/activemq/conf"]}, "os": {"distro": "debian", "release": "9", "package_manager": "apt", "repos_reachable": True, "tools": ["apt", "apt-get", "awk", "base64", "bash", "cat", "chattr", "chmod", "chown", "cp", "cron", "crontab", "curl", "cut", "dash", "dpkg", "dpkg-query", "egrep", "find", "findmnt", "getent", "grep", "gzip", "head", "hostname", "ip", "java", "javac", "ls", "mkdir", "mount", "mv", "od", "openssl", "perl", "ping", "readlink", "realpath", "rm", "sed", "service", "sh", "sort", "ss", "tail", "tar", "touch", "tr", "uname", "uniq", "wget", "xargs"]}, "filesystem": {"exec_user": "root", "writable": ["/dev/shm", "/etc", "/home", "/opt", "/opt/activemq", "/opt/activemq/conf", "/opt/apache-activemq-5.11.1", "/opt/jdk/bin", "/root", "/run", "/srv", "/tmp", "/usr", "/usr/bin", "/usr/lib", "/usr/local", "/var", "/var/lib"], "mounts": [], "volatile_paths": ["/dev/shm", "/run", "/tmp"], "capabilities": ["default"], "init_system": False, "read_only_rootfs": False}, "config_lifecycle": {"applies_on_restart": True, "main_pid_is_1": False}}, "vulnerability_details": {"IP": "192.168.20.58", "Hostname": "fedora", "Port": "8161", "Port Protocol": "tcp", "CVSS": "10.0", "Severity": "Critical", "QoD": "98", "Solution Type": "Mitigation", "NVT Name": "Apache ActiveMQ Web Console Default / No Credentials (HTTP)", "Summary": "The Apache ActiveMQ Web Console is unprotected or is using\n  default credentials.", "Specific Result": "It was possible to access the Apache ActiveMQ Web Console at:\n\nhttp://fedora:8161/admin/index.jsp using user \"admin\" with password \"admin\"\n\nhttp://fedora:8161/admin/index.jsp using user \"user\" with password \"user\"\n", "NVT OID": "1.3.6.1.4.1.25623.1.0.108253", "CVEs": "", "Task ID": "e966c840-9e4c-47a4-b8e0-d491fca2e4b3", "Task Name": "self-scan", "Timestamp": "2026-07-06T19:16:40Z", "Result ID": "a1f09060-151a-493c-9c5b-99cc3b514a9d", "Impact": "This issue may be exploited by a remote attacker to gain access\n  to sensitive information.", "Solution": "Change or set the password.", "Affected Software/OS": "", "Vulnerability Insight": "", "Vulnerability Detection Method": "\nDetails:\nApache ActiveMQ Web Console Default / No Credentials (HTTP)\n(OID: 1.3.6.1.4.1.25623.1.0.108253)\nVersion used: 2023-02-28T10:20:42Z\n", "Product Detection Result": "", "BIDs": "", "CERTs": "", "Other References": ""}}

patch = '''
#!/bin/bash
set -euo pipefail
umask 077
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

find_realm() {
    local candidate found
    for candidate in \
        /opt/activemq/conf/jetty-realm.properties \
        /opt/apache-activemq-5.11.1/conf/jetty-realm.properties
    do
        if [ -f "$candidate" ]; then
            readlink -f "$candidate"
            return 0
        fi
    done

    found="$(find /opt /usr/local /srv /var/lib -type f -name jetty-realm.properties 2>/dev/null | head -n 1 || true)"
    if [ -n "$found" ] && [ -f "$found" ]; then
        readlink -f "$found"
        return 0
    fi

    return 1
}

generate_password() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 24
    else
        od -An -N24 -tx1 /dev/urandom | tr -d ' \n'
    fi
}

realm="$(find_realm)" || {
    echo "ERROR: could not locate ActiveMQ jetty-realm.properties" >&2
    exit 1
}

conf_dir="$(dirname "$realm")"
admin_password="$(generate_password)"
user_password="$(generate_password)"
while [ "$admin_password" = "$user_password" ]; do
    user_password="$(generate_password)"
done

if command -v chattr >/dev/null 2>&1; then
    chattr -i "$realm" 2>/dev/null || true
fi

tmp="$(mktemp "${conf_dir}/.jetty-realm.properties.XXXXXX")"
cleanup() {
    rm -f "$tmp"
}
trap cleanup EXIT

awk -v apw="$admin_password" -v upw="$user_password" '
function trim(s) {
    sub(/^[[:space:]]+/, "", s)
    sub(/[[:space:]]+$/, "", s)
    return s
}
/^[[:space:]]*#/ || /^[[:space:]]*$/ {
    print
    next
}
{
    line = $0
    colon = index(line, ":")
    if (colon == 0) {
        print
        next
    }

    username = trim(substr(line, 1, colon - 1))
    rest = substr(line, colon + 1)
    sub(/\r$/, "", rest)
    sub(/^[[:space:]]+/, "", rest)

    roles = ""
    comma = index(rest, ",")
    if (comma > 0) {
        roles = substr(rest, comma)
    }

    if (username == "admin") {
        print "admin: " apw roles
    } else if (username == "user") {
        print "user: " upw roles
    } else {
        print
    }
}' "$realm" > "$tmp"

if ! grep -Eq '^[[:space:]]*admin[[:space:]]*:' "$tmp"; then
    printf 'admin: %s, admin\n' "$admin_password" >> "$tmp"
fi

if ! grep -Eq '^[[:space:]]*user[[:space:]]*:' "$tmp"; then
    printf 'user: %s, user\n' "$user_password" >> "$tmp"
fi

has_default_credentials() {
    grep -Eq '^[[:space:]]*(admin[[:space:]]*:[[:space:]]*admin|user[[:space:]]*:[[:space:]]*user)([[:space:]]*,|[[:space:]]*$)' "$1"
}

if has_default_credentials "$tmp"; then
    echo "ERROR: generated Jetty realm still contains default credentials" >&2
    exit 1
fi

# Write back into the existing file so its ownership and permissions are preserved.
cat "$tmp" > "$realm"

if has_default_credentials "$realm"; then
    echo "ERROR: ActiveMQ Jetty realm still contains default credentials" >&2
    exit 1
fi

credentials_file="/root/activemq-web-console-credentials.txt"
{
    printf '# ActiveMQ web console credentials\n'
    printf '# Generated: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '# Configuration: %s\n' "$realm"
    printf 'admin: %s\n' "$admin_password"
    printf 'user: %s\n' "$user_password"
} > "$credentials_file" || true

chmod 600 "$credentials_file" 2>/dev/null || true

printf 'Rotated ActiveMQ web console credentials. New credentials stored in %s\n' "$credentials_file"
'''

generator = Generator()
judge = Judge()

print(judge.judge(
    model='deepseek_flash', 
    patches={'deepseek_flash': patch},
    environment_details=details["environment_details"],
    vulnerability_details=details["vulnerability_details"]
))