```bash
#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Error: Root privileges required" >&2
    exit 1
fi

KIBANA_SERVICE="kibana"

if systemctl is-active --quiet "$KIBANA_SERVICE"; then
    systemctl stop "$KIBANA_SERVICE"
fi

if systemctl is-enabled --quiet "$KIBANA_SERVICE"; then
    systemctl disable "$KIBANA_SERVICE"
fi

if [ -f /etc/systemd/system/$KIBANA_SERVICE.service ]; then
    rm -f /etc/systemd/system/$KIBANA_SERVICE.service
elif [ -f /usr/lib/systemd/system/$KIBANA_SERVICE.service ]; then
    rm -f /usr/lib/systemd/system/$KIBANA_SERVICE.service
fi

systemctl daemon-reload
```