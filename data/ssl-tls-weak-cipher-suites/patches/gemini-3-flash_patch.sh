```bash
#!/bin/bash
set -euo pipefail

# Ensure the script is executed with root privileges
if [ "$(id -u)" -ne 0 ]; then
    exit 1
fi

# Define the hardened cipher suite string to mitigate CVE-2013-2566, CVE-2015-2808, and CVE-2015-4000
# Specifically excludes SEED, RC4, MD5, and low-strength export ciphers
HARDENED_CIPHERS="HIGH:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!3DES:!MD5:!PSK:!SEED"

# Locate PostgreSQL configuration files within the environment
# Port 5432 indicates a PostgreSQL service
CONF_FILES=$(find /etc/postgresql -name "postgresql.conf" 2>/dev/null || true)

for conf in $CONF_FILES; do
    # Check if the ssl_ciphers parameter is already set to the hardened string
    if ! grep -q "^ssl_ciphers = '$HARDENED_CIPHERS'" "$conf"; then
        # If the parameter exists (commented or otherwise), replace it surgically
        if grep -q "^#\?ssl_ciphers =" "$conf"; then
            sed -i "s|^#\?ssl_ciphers =.*|ssl_ciphers = '$HARDENED_CIPHERS'|" "$conf"
        else
            # If the parameter is missing, append it to the configuration
            echo "ssl_ciphers = '$HARDENED_CIPHERS'" >> "$conf"
        fi

        # Reload the service to apply changes without terminating active connections
        # Silent failure if the service manager is not present or service is not running
        systemctl reload postgresql 2>/dev/null || true
    fi
done
```