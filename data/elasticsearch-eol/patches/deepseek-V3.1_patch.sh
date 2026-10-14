```bash
#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

SERVICE_NAME="elasticsearch"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
SERVICE_ENABLED=$(systemctl is-enabled "$SERVICE_NAME" 2>/dev/null || echo "inactive")

if [ -f "$SERVICE_FILE" ] || [ "$SERVICE_ENABLED" != "inactive" ]; then
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
fi

if dpkg -l | grep -q "elasticsearch"; then
    apt-get remove --purge -y elasticsearch >/dev/null 2>&1
fi

if [ -d "/etc/elasticsearch" ]; then
    rm -rf /etc/elasticsearch
fi

if [ -d "/var/lib/elasticsearch" ]; then
    rm -rf /var/lib/elasticsearch
fi

if [ -d "/usr/share/elasticsearch" ]; then
    rm -rf /usr/share/elasticsearch
fi
```