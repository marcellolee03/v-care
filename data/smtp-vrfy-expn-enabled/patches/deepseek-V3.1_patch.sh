```bash
#!/bin/bash
set -euo pipefail

readonly POSTFIX_CFG="/etc/postfix/main.cf"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Check if Postfix is installed and the config file exists
if ! command -v postconf >/dev/null 2>&1; then
    echo "Error: Postfix is not installed" >&2
    exit 1
fi

if [ ! -f "$POSTFIX_CFG" ]; then
    echo "Error: Postfix configuration file not found at $POSTFIX_CFG" >&2
    exit 1
fi

# Disable VRFY and EXPN commands
postconf -e "disable_vrfy_command = yes"
postconf -e "smtpd_discard_ehlo_keywords = vrfy, expn"

# Reload Postfix to apply changes
if systemctl is-active --quiet postfix; then
    systemctl reload postfix
fi
```