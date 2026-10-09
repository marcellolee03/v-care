```bash
#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
    echo "Error: systemctl not found" >&2
    exit 1
fi

TELNET_SERVICE="telnet.socket"

if systemctl is-active --quiet "$TELNET_SERVICE"; then
    systemctl stop "$TELNET_SERVICE"
    systemctl disable "$TELNET_SERVICE"
fi
```