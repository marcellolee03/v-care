```bash
#!/bin/bash
set -euo pipefail

readonly CONFIG_PATH="/etc/proftpd/proftpd.conf"
readonly MOD_COPY_CONFIG="LoadModule mod_copy.c"
readonly TEMP_CONFIG=$(mktemp)

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Check if ProFTPD configuration exists
if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "Error: ProFTPD configuration file not found at $CONFIG_PATH" >&2
    exit 1
fi

# Remove mod_copy module loading from configuration
grep -v "$MOD_COPY_CONFIG" "$CONFIG_PATH" > "$TEMP_CONFIG"

# Verify change was made
if ! grep -q "$MOD_COPY_CONFIG" "$TEMP_CONFIG"; then
    mv "$TEMP_CONFIG" "$CONFIG_PATH"
else
    rm -f "$TEMP_CONFIG"
fi

# Restart ProFTPD if it's running
if systemctl is-active --quiet proftpd; then
    systemctl restart proftpd
elif service proftpd status >/dev/null 2>&1; then
    service proftpd restart
fi

exit 0
```