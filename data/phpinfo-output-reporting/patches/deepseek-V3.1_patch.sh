```bash
#!/bin/bash
set -euo pipefail

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Target file containing phpinfo() call
PHPINFO_FILE="/var/www/html/phpinfo.php"

# Remove the phpinfo.php file if it exists
if [[ -f "$PHPINFO_FILE" ]]; then
    rm -f "$PHPINFO_FILE"
    
    # Restart Apache to ensure the change takes effect
    if systemctl is-active --quiet apache2; then
        systemctl reload apache2
    fi
fi

exit 0
```