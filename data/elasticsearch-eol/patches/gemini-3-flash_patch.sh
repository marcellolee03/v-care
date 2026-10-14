```bash
#!/bin/bash
set -euo pipefail

# Role: Senior System Security Engineer
# Task: Mitigate Elasticsearch End of Life (EOL) Vulnerability
# Logic: Stop, disable, and remove EOL software to eliminate security risk.

# Verify root privileges
if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

SERVICE_NAME="elasticsearch"

# Stop and mask the service to prevent execution and port binding
if systemctl list-unit-files "${SERVICE_NAME}.service" >/dev/null 2>&1; then
    systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
    systemctl mask "${SERVICE_NAME}" 2>/dev/null || true
fi

# Purge the EOL package if managed by the package manager
if dpkg-query -W -f='${Status}' "${SERVICE_NAME}" 2>/dev/null | grep -q "ok installed"; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get purge -y -qq "${SERVICE_NAME}" >/dev/null 2>&1
    apt-get autoremove -y -qq >/dev/null 2>&1
fi
```