```bash
#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Error: Root privileges required" >&2
    exit 1
fi

APACHE_CONFIG_DIR="/etc/apache2"
CONFIG_FILES=("apache2.conf" "httpd.conf")

for config_file in "${CONFIG_FILES[@]}"; do
    config_path="${APACHE_CONFIG_DIR}/${config_file}"
    if [ -f "$config_path" ]; then
        if grep -q "^\s*Require all denied" "$config_path" 2>/dev/null; then
            continue
        fi
        
        sed -i '/^\s*<Directory\s\+.*>\s*$/,/^\s*<\/Directory\s*>\s*$/ {
            /^\s*Options\s\+.*ExecCGI/!b
            :a; n; /^\s*<\/Directory\s*>/!ba
            i\
            Require all denied
        }' "$config_path"
        
        break
    fi
done

if systemctl is-active --quiet apache2; then
    systemctl reload apache2
fi
```