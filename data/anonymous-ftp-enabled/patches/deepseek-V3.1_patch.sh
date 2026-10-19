```bash
#!/bin/bash

set -euo pipefail

readonly FTP_CONFIG_FILE="/etc/vsftpd.conf"
readonly FTP_CONFIG_DIR="/etc/vsftpd"

# Verify root privileges
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Check if vsftpd is installed
if ! command -v vsftpd >/dev/null 2>&1; then
    echo "Error: vsftpd is not installed" >&2
    exit 1
fi

# Determine the main configuration file location
config_file=""
if [[ -f "$FTP_CONFIG_FILE" ]]; then
    config_file="$FTP_CONFIG_FILE"
elif [[ -d "$FTP_CONFIG_DIR" && -f "${FTP_CONFIG_DIR}/vsftpd.conf" ]]; then
    config_file="${FTP_CONFIG_DIR}/vsftpd.conf"
else
    echo "Error: Could not find vsftpd configuration file" >&2
    exit 1
fi

# Create backup of configuration file
backup_file="${config_file}.bak.$(date +%Y%m%d%H%M%S)"
cp "$config_file" "$backup_file"

# Disable anonymous FTP access
if grep -q "^anonymous_enable" "$config_file"; then
    # Update existing anonymous_enable directive
    sed -i 's/^anonymous_enable=.*/anonymous_enable=NO/' "$config_file"
else
    # Add anonymous_enable directive
    echo "anonymous_enable=NO" >> "$config_file"
fi

# Restart vsftpd service to apply changes
if systemctl is-active --quiet vsftpd; then
    systemctl restart vsftpd >/dev/null 2>&1
fi

exit 0
```