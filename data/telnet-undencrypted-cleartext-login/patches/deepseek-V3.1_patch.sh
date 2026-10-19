```bash
#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

readonly TELNET_SERVICE="telnet.socket"
readonly TELNET_PORT="2323/tcp"

if systemctl is-active --quiet "$TELNET_SERVICE"; then
    systemctl stop "$TELNET_SERVICE"
    systemctl disable "$TELNET_SERVICE"
fi

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    ufw deny "$TELNET_PORT"
fi
```