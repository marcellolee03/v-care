```bash
#!/bin/bash
set -euo pipefail

readonly SVC_NAME="rexec.socket"
readonly PORT=512

# Require root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Stop and disable the rexec service if it exists and is active
if systemctl list-unit-files --type=service,socket | grep -q "$SVC_NAME"; then
    systemctl stop "$SVC_NAME" 2>/dev/null || true
    systemctl disable "$SVC_NAME" 2>/dev/null || true
fi

# Block the rexec port using iptables if available
if command -v iptables >/dev/null 2>&1; then
    if ! iptables -C INPUT -p tcp --dport "$PORT" -j DROP 2>/dev/null; then
        iptables -A INPUT -p tcp --dport "$PORT" -j DROP
    fi
fi

# Verify the service is no longer listening on the port
if command -v ss >/dev/null 2>&1; then
    if ss -tln | grep -q ":$PORT "; then
        echo "Warning: Port $PORT is still listening. Manual investigation required." >&2
        exit 1
    fi
fi
```