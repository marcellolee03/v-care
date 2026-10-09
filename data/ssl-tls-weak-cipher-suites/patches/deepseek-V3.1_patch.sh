```bash
#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

CONF_FILE="/etc/postgresql/$(ls /etc/postgresql | sort -V | tail -n1)/main/postgresql.conf"
TEMP_FILE="$(mktemp)"

if [ ! -f "$CONF_FILE" ]; then
    echo "Error: PostgreSQL configuration file not found" >&2
    exit 1
fi

if grep -q "^ssl_ciphers" "$CONF_FILE"; then
    awk '
    /^ssl_ciphers/ {
        if (!/-SEED-CBC-SHA:/ && !/SEED-CBC-SHA,/) {
            gsub("SEED-CBC-SHA", "")
            gsub(",,", ",")
            sub(",$", "")
            sub("^,", "")
        }
        if ($0 !~ /SEED-CBC-SHA/) print $0
        next
    }
    { print }
    ' "$CONF_FILE" > "$TEMP_FILE"
else
    awk -v ciphers_line="ssl_ciphers = 'HIGH:!aNULL:!MD5:!SEED-CBC-SHA'" '
    /^#ssl_ciphers/ {
        print ciphers_line
        next
    }
    { print }
    END {
        if (!found) print ciphers_line
    }' "$CONF_FILE" > "$TEMP_FILE"
fi

if ! diff -q "$CONF_FILE" "$TEMP_FILE" >/dev/null; then
    cp "$TEMP_FILE" "$CONF_FILE"
    chmod 644 "$CONF_FILE"
    systemctl reload postgresql 2>/dev/null || /etc/init.d/postgresql reload 2>/dev/null || true
fi

rm -f "$TEMP_FILE"
```