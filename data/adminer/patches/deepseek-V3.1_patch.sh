```bash
#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Error: Root privileges required" >&2
    exit 1
fi

readonly adminer_dir="/usr/share/adminer"
readonly adminer_port="8080"

if [ ! -d "$adminer_dir" ]; then
    echo "Error: Adminer directory not found at $adminer_dir" >&2
    exit 1
fi

if ! command -v nginx >/dev/null 2>&1; then
    echo "Error: NGINX is not installed" >&2
    exit 1
fi

readonly nginx_conf_dir="/etc/nginx"
readonly nginx_sites_available="$nginx_conf_dir/sites-available"
readonly nginx_sites_enabled="$nginx_conf_dir/sites-enabled"

if [ -f "$nginx_sites_enabled/adminer" ]; then
    rm -f "$nginx_sites_enabled/adminer"
fi

if [ -f "$nginx_sites_available/adminer" ]; then
    rm -f "$nginx_sites_available/adminer"
fi

nginx -t && systemctl reload nginx

if systemctl is-active --quiet "adminer.service" 2>/dev/null; then
    systemctl stop adminer.service
    systemctl disable adminer.service
fi

if netstat -tuln | grep -q ":$adminer_port "; then
    pkill -f "adminer" || true
fi

exit 0
```