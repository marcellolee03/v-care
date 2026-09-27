```bash
#!/bin/bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" >&2
    exit 1
fi

config_file="/vendor/web.config"
nginx_config_dir="/etc/nginx"
nginx_config_file="${nginx_config_dir}/nginx.conf"
backup_file="${nginx_config_file}.bak"

if [[ ! -d "$nginx_config_dir" ]]; then
    echo "Nginx configuration directory not found: $nginx_config_dir" >&2
    exit 1
fi

if [[ ! -f "$nginx_config_file" ]]; then
    echo "Nginx configuration file not found: $nginx_config_file" >&2
    exit 1
fi

cp "$nginx_config_file" "$backup_file"

if ! grep -q "location.*${config_file}" "$nginx_config_file"; then
    awk -v config="$config_file" '
    /^[[:space:]]*server[[:space:]]*\{/ {
        print
        while (getline && !/^[[:space:]]*\}/) {
            if (/^[[:space:]]*location[[:space:]]*\/[[:space:]]*\{/) {
                print
                in_root_location=1
                continue
            }
            if (in_root_location && /^[[:space:]]*}/) {
                print "    location " config " {"
                print "        deny all;"
                print "        return 403;"
                print "    }"
                in_root_location=0
            }
            print
        }
        if (in_root_location) {
            print "    location " config " {"
            print "        deny all;"
            print "        return 403;"
            print "    }"
            in_root_location=0
        }
        print
        next
    }
    { print }
 "${nginx_config_file}.tmp" "$nginx_config_file"
fi

if nginx -t > /dev/null 2>&1; then
    systemctl reload nginx
else
    echo "Nginx configuration test failed. Restoring backup." >&2
    mv "$backup_file" "$nginx_config_file"
    exit 1
fi
```