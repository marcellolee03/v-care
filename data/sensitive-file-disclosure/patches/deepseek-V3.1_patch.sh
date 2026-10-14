```bash
#!/bin/bash

# Exit on error, undefined variable, and pipe failure
set -euo pipefail

# Verify root privileges
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Configuration parameters
WEB_CONFIG_PATH="web.config"
SITE_DIR="/var/www/html"
TEST_PORT=8088

# Check if the vulnerable file exists
if [[ ! -f "${SITE_DIR}/${WEB_CONFIG_PATH}" ]]; then
    echo "Error: ${WEB_CONFIG_PATH} not found in ${SITE_DIR}" >&2
    exit 1
fi

# Restrict permissions to root read-only
chmod 600 "${SITE_DIR}/${WEB_CONFIG_PATH}"
chown root:root "${SITE_DIR}/${WEB_CONFIG_PATH}"

# Configure web server to block access to web.config
APACHE_CONF="/etc/apache2/apache2.conf"
NGINX_CONF="/etc/nginx/nginx.conf"

# Check for Apache
if [[ -d "/etc/apache2" ]]; then
    if ! grep -q "Files ${WEB_CONFIG_PATH}" /etc/apache2/conf-available/security.conf 2>/dev/null; then
        echo -e "\n<Files \"${WEB_CONFIG_PATH}\">\n    Require all denied\n</Files>" \
            >> /etc/apache2/conf-available/security.conf
        systemctl reload apache2
    fi
fi

# Check for Nginx
if [[ -d "/etc/nginx" ]]; then
    NGINX_SITES="/etc/nginx/sites-enabled/*"
    for site in ${NGINX_SITES}; do
        if [[ -f "${site}" ]] && ! grep -q "location ~ /${WEB_CONFIG_PATH}" "${site}"; then
            sed -i '/server {/a\    location ~ /web\.config {\n        deny all;\n    }' "${site}"
        fi
    done
    systemctl reload nginx
fi

# Test the fix if curl is available
if command -v curl >/dev/null 2>&1; then
    if curl -fs "http://localhost:${TEST_PORT}/${WEB_CONFIG_PATH}" >/dev/null 2>&1; then
        echo "Warning: File still accessible via HTTP" >&2
        exit 1
    fi
fi
```