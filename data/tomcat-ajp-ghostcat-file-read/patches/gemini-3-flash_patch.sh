```bash
#!/bin/bash
set -euo pipefail

# Verify root privileges
if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# Locate Tomcat configuration files in common installation paths
# Debian 10 typically uses /etc/tomcat9/server.xml
CONFIG_FILES=$(find /etc /opt /usr/share -name "server.xml" -type f 2>/dev/null || true)

for cfg in $CONFIG_FILES; do
    # Verify file is writable
    [[ ! -w "$cfg" ]] && continue

    # Mitigate Ghostcat (CVE-2020-1938) by commenting out the AJP connector on port 8009.
    # Logic:
    # 1. Target lines containing both port="8009" and protocol="AJP/1.3".
    # 2. Check if the line is already commented (does not contain '<!--').
    # 3. If active, wrap the XML tag in comments.
    # This approach is surgical and idempotent.
    sed -i '/port="8009"/ { /protocol="AJP\/1\.3"/ { /<!--/! s/^\(\s*\)\(<[^>]*>\)/\1<!-- \2 -->/ } }' "$cfg"
done

# Restart Tomcat services if systemctl is available to apply the configuration change
if command -v systemctl >/dev/null 2>&1; then
    # Identify active tomcat-related services
    TOMCAT_SERVICES=$(systemctl list-units --type=service --state=running --no-legend "tomcat*" | awk '{print $1}')
    for svc in $TOMCAT_SERVICES; do
        systemctl restart "$svc" >/dev/null 2>&1 || true
    done
fi
```