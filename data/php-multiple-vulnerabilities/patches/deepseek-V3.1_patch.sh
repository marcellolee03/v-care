```bash
#!/bin/bash
set -euo pipefail

# Verify root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

php_ini_dir="/usr/local/etc/php"
cgi_conf_dir="/etc/apache2"

# Disable the vulnerable CGI mode if Apache is installed and configured
if [ -d "$cgi_conf_dir" ]; then
    # Check if mod_php is available and switch from CGI to mod_php
    if a2query -m php5 2>/dev/null || a2query -m php7 2>/dev/null; then
        # Disable CGI configuration
        for conf in $(find "$cgi_conf_dir" -name "*cgi*" -type f | grep -E "\.(conf|load)$"); do
            if [ -f "$conf" ]; then
                sed -i '/^[[:space:]]*LoadModule.*cgi/s/^/#/' "$conf"
            fi
        done
        systemctl reload apache2
    fi
fi

# Hardened php.ini configuration to prevent code execution
if [ -d "$php_ini_dir" ]; then
    for php_ini in "$php_ini_dir"/php.ini "$php_ini_dir"/php.d/*.ini; do
        if [ -f "$php_ini" ]; then
            # Disable dangerous PHP functions and features
            sed -i 's/^\(allow_url_include\s*=\s*\).*/\1Off/' "$php_ini"
            sed -i 's/^\(auto_prepend_file\s*=\s*\).*/\1/' "$php_ini"
            sed -i 's/^\(enable_dl\s*=\s*\).*/\1Off/' "$php_ini"
            sed -i '\).*/\1On/' "$php_ini"
            sed -i 's/^\(display_errors\s*=\s*\).*/\1Off/' "$php_ini"
        fi
    done
fi

# Apply the most secure PHP handler if available
if command -v phpdismod >/dev/null 2>&1; then
    phpdismod cgi 2>/dev/null || true
    phpdismod fpm 2>/dev/null || true
    phpenmod php5 2>/dev/null || phpenmod php7 2>/dev/null || true
fi
```