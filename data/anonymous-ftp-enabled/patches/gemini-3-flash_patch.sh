```bash
#!/bin/bash

# CVE-1999-0497 Mitigation Script
# Description: Disables anonymous FTP login for vsftpd, proftpd, and pure-ftpd.
# Environment: Pop!_OS (Ubuntu/Debian-based)

set -euo pipefail

# Ensure the script is executed with root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Root privileges required." >&2
    exit 1
fi

# 1. vsftpd mitigation
VSFTPD_CONF="/etc/vsftpd.conf"
if [ -f "$VSFTPD_CONF" ]; then
    if grep -qi "^anonymous_enable" "$VSFTPD_CONF"; then
        sed -i 's/^[#[:space:]]*anonymous_enable[[:space:]]*=.*/anonymous_enable=NO/I' "$VSFTPD_CONF"
    else
        echo "anonymous_enable=NO" >> "$VSFTPD_CONF"
    fi
    systemctl restart vsftpd >/dev/null 2>&1 || true
fi

# 2. Pure-FTPd mitigation
# Pure-FTPd uses a directory-based configuration system
PURE_CONF_DIR="/etc/pure-ftpd/conf"
if [ -d "$PURE_CONF_DIR" ]; then
    echo "yes" > "$PURE_CONF_DIR/NoAnonymous"
    # Restart any active pure-ftpd variants
    systemctl restart pure-ftpd >/dev/null 2>&1 || true
    systemctl restart pure-ftpd-mysql >/dev/null 2>&1 || true
    systemctl restart pure-ftpd-postgresql >/dev/null 2>&1 || true
fi

# 3. ProFTPD mitigation
PROFTPD_CONF="/etc/proftpd/proftpd.conf"
if [ -f "$PROFTPD_CONF" ]; then
    # Comment out the <Anonymous> block if it exists and is active
    # This matches from the start tag to the end tag and prepends a # to each line
    sed -i '/<Anonymous/,/<\/Anonymous>/ s/^\([^#]\)/#\1/' "$PROFTPD_CONF"
    systemctl restart proftpd >/dev/null 2>&1 || true
fi

exit 0
```