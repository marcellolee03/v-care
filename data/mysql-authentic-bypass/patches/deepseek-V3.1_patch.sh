```bash
#!/bin/bash
set -euo pipefail

# Verify root privileges
if [ "$EUID" -ne 0 ]; then 
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Variables
CONFIG_FILE="/etc/mysql/my.cnf"
AUTH_PLUGIN_SETTING="default_authentication_plugin"

# Check if MySQL/MariaDB is installed
if ! command -v mysql > /dev/null 2>&1; then
    echo "Error: MySQL/MariaDB not found" >&2
    exit 1
fi

# Check if configuration file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found: $CONFIG_FILE" >&2
    exit 1
fi

# Check if the vulnerability fix is already applied
if grep -q "^[[:space:]]*$AUTH_PLUGIN_SETTING[[:space:]]*=" "$CONFIG_FILE"; then
    # Already configured - verify it's set to mysql_native_password
    if grep -q "^[[:space:]]*$AUTH_PLUGIN_SETTING[[:space:]]*=[[:space:]]*mysql_native_password" "$CONFIG_FILE"; then
        exit 0  # Already mitigated
    else
        # Update existing setting to mysql_native_password
        sed -i "s/^[[:space:]]*$AUTH_PLUGIN_SETTING[[:space:]]*=.*/$AUTH_PLUGIN_SETTING = mysql_native_password/" "$CONFIG_FILE"
    fi
else
    # Add the mitigation setting
    echo "" >> "$CONFIG_FILE"
    echo "# CVE-2012-2122 mitigation - Force native password authentication" >> "$CONFIG_FILE"
    echo "$AUTH_PLUGIN_SETTING = mysql_native_password" >> "$CONFIG_FILE"
fi

# Restart MySQL service to apply changes
if systemctl is-active --quiet mysql 2>/dev/null || systemctl is-active --quiet mariadb 2>/dev/null; then
    # Determine which service name is used
    if systemctl list-unit-files | grep -q '^mysql.service'; then
        systemctl restart mysql
    else
        systemctl restart mariadb
    fi
fi
```