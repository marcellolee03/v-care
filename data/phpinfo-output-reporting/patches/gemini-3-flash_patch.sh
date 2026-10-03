```bash
#!/bin/bash
set -euo pipefail

# Ensure the script is executed with root privileges
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# Define paths based on vulnerability report and system context
TARGET_FILE="/var/www/html/phpinfo.php"
PHP_CONFIG="/etc/php/8.1/apache2/php.ini"

# Mitigation 1: Delete the specific file identified in the vulnerability report
# rm -f is idempotent as it does not error if the file is already missing
if [[ -f "$TARGET_FILE" ]]; then
    rm -f "$TARGET_FILE"
fi

# Mitigation 2: Harden PHP configuration by disabling the phpinfo function globally
if [[ -f "$PHP_CONFIG" ]]; then
    # Check if phpinfo is already in the disable_functions directive
    if ! grep -qi "^disable_functions.*phpinfo" "$PHP_CONFIG"; then
        
        # Case 1: directive is commented out
        if grep -q "^;disable_functions =" "$PHP_CONFIG"; then
            sed -i 's/^;disable_functions =/disable_functions = phpinfo/' "$PHP_CONFIG"
        
        # Case 2: directive exists but is empty or contains other functions
        elif grep -q "^disable_functions =" "$PHP_CONFIG"; then
            sed -i 's/^disable_functions =/disable_functions = phpinfo,/' "$PHP_CONFIG"
        
        # Case 3: directive does not exist in the file
        else
            echo "disable_functions = phpinfo" >> "$PHP_CONFIG"
        fi

        # Mitigation 3: Reload the web server to apply configuration changes
        if command -v systemctl >/dev/null 2>&1; then
            if systemctl is-active --quiet apache2; then
                systemctl reload apache2 >/dev/null 2>&1 || true
            fi
        fi
    fi
fi
```