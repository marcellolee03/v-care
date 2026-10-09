```bash
#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

CONFIG_FILES="/etc/apache2/apache2.conf /etc/apache2/conf-enabled/*.conf /etc/apache2/sites-enabled/*.conf"

for config_file in $CONFIG_FILES; do
    if [ -f "$config_file" ]; then
        if grep -q "^[[:space:]]*TraceEnable[[:space:]]" "$config_file"; then
            sed -i 's/^[[:space:]]*TraceEnable[[:space:]]*.*/TraceEnable Off/' "$config_file"
        else
            if ! grep -q "^[[:space:]]*TraceEnable[[:space:]]*Off" "$config_file"; then
                echo "TraceEnable Off" >> "$config_file"
            fi
        fi
    fi
done

if systemctl is-active --quiet apache2; then
    systemctl reload apache2
fi
```