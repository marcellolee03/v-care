```bash
#!/bin/bash
# Description: Mitigates "Anonymous FTP Login Reporting" vulnerability (CVE-1999-0497)
#              by disabling anonymous FTP access for common FTP servers (vsftpd, proftpd, pure-ftpd).
# Environment: Linux (Pop!_OS/Ubuntu-based), using native commands.

set -euo pipefail

# --- Pre-requisites and Error Handling ---

# Verify script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# --- Mitigation Logic ---

FTP_SERVER_FIXED=false

# 1. Mitigate vsftpd vulnerability
# Check if vsftpd process is running
if ps aux | grep -q '[v]sftpd'; then
    VSFTPD_CONF="/etc/vsftpd.conf"
    # Check if vsftpd configuration file exists
    if [ -f "$VSFTPD_CONF" ]; then
        # Ensure anonymous_enable is set to NO, handling existing lines (commented or uncommented) and adding if missing.
        if grep -qE '^\s*#?\s*anonymous_enable=' "$VSFTPD_CONF"; then
            sed -i -E 's/^\s*#?\s*anonymous_enable=.*$/anonymous_enable=NO/' "$VSFTPD_CONF" || \
                { echo "Error: Failed to modify 'anonymous_enable' in $VSFTPD_CONF." >&2; exit 1; }
        else
            echo "anonymous_enable=NO" >> "$VSFTPD_CONF" || \
                { echo "Error: Failed to add 'anonymous_enable' to $VSFTPD_CONF." >&2; exit 1; }
        fi
        
        # Best practice: Also disable anonymous uploads and directory creation to prevent potential misuse.
        if grep -qE '^\s*#?\s*anon_upload_enable=' "$VSFTPD_CONF"; then
            sed -i -E 's/^\s*#?\s*anon_upload_enable=.*$/anon_upload_enable=NO/' "$VSFTPD_CONF" || \
                { echo "Error: Failed to modify 'anon_upload_enable' in $VSFTPD_CONF." >&2; exit 1; }
        else
            echo "anon_upload_enable=NO" >> "$VSFTPD_CONF" || \
                { echo "Error: Failed to add 'anon_upload_enable' to $VSFTPD_CONF." >&2; exit 1; }
        fi
        
        if grep -qE '^\s*#?\s*anon_mkdir_write_enable=' "$VSFTPD_CONF"; then
            sed -i -E 's/^\s*#?\s*anon_mkdir_write_enable=.*$/anon_mkdir_write_enable=NO/' "$VSFTPD_CONF" || \
                { echo "Error: Failed to modify 'anon_mkdir_write_enable' in $VSFTPD_CONF." >&2; exit 1; }
        else
            echo "anon_mkdir_write_enable=NO" >> "$VSFTPD_CONF" || \
                { echo "Error: Failed to add 'anon_mkdir_write_enable' to $VSFTPD_CONF." >&2; exit 1; }
        fi
        
        # Restart vsftpd service to apply changes.
        systemctl restart vsftpd.service || { echo "Error: Failed to restart vsftpd service. Please check vsftpd configuration and service status." >&2; exit 1; }
        FTP_SERVER_FIXED=true
    fi
fi

# 2. Mitigate proftpd vulnerability
# Only attempt if vsftpd was not detected/fixed (to avoid conflicts if multiple FTP servers are present)
if ! "$FTP_SERVER_FIXED" && ps aux | grep -q '[p]roftpd'; then
    PROFTPD_CONF="/etc/proftpd/proftpd.conf"
    if [ -f "$PROFTPD_CONF" ]; then
        # Ensure 'AllowAnonymous off' is set in the main config.
        # This will change it if 'on' or 'AllowAnonymous' is explicitly defined, or add it if missing.
        if grep -qE '^\s*AllowAnonymous\s+(on|off)' "$PROFTPD_CONF"; then
            sed -i -E 's/^\s*AllowAnonymous\s+on/AllowAnonymous off/' "$PROFTPD_CONF" || \
                { echo "Error: Failed to modify 'AllowAnonymous' in $PROFTPD_CONF." >&2; exit 1; }
        else
            # Add at the end of the file if not found, with a newline for clarity.
            echo -e "\nAllowAnonymous off" >> "$PROFTPD_CONF" || \
                { echo "Error: Failed to add 'AllowAnonymous' to $PROFTPD_CONF." >&2; exit 1; }
        fi

        # Robustly disable anonymous access by commenting out any <Anonymous> ... </Anonymous> blocks.
        # This uses awk for multi-line block manipulation and mktemp for atomic file update.
        AWK_TEMP_FILE=$(mktemp)
        awk '
        /^\s*<Anonymous>/ { in_anonymous_block=1; print "#" $0; next }
        /^\s*<\/Anonymous>/ { in_anonymous_block=0; print "#" $0; next }
        in_anonymous_block { print "#" $0; next }
        { print }
        ' "$PROFTPD_CONF" > "$AWK_TEMP_FILE" && mv "$AWK_TEMP_FILE" "$PROFTPD_CONF" || \
        { rm -f "$AWK_TEMP_FILE"; echo "Error: Failed to comment out anonymous blocks in $PROFTPD_CONF." >&2; exit 1; }
        
        # Restart proftpd service to apply changes.
        systemctl restart proftpd.service || { echo "Error: Failed to restart proftpd service. Please check proftpd configuration and service status." >&2; exit 1; }
        FTP_SERVER_FIXED=true
    fi
fi

# 3. Mitigate pure-ftpd vulnerability
# Only attempt if no other server was detected/fixed
if ! "$FTP_SERVER_FIXED" && ps aux | grep -q '[p]ure-ftpd'; then
    PUREFTPD_CONF_DIR="/etc/pure-ftpd/conf"
    if [ -d "$PUREFTPD_CONF_DIR" ]; then
        ANON_CONF_FILE="$PUREFTPD_CONF_DIR/NoAnonymous"

        # Check if NoAnonymous is a symlink (often to /dev/null to ENABLE anonymous access)
        if [ -L "$ANON_CONF_FILE" ]; then
            rm "$ANON_CONF_FILE" || { echo "Error: Failed to remove symlink for pure-ftpd NoAnonymous." >&2; exit 1; }
            echo "yes" > "$ANON_CONF_FILE" || { echo "Error: Failed to create pure-ftpd NoAnonymous file." >&2; exit 1; }
        # Check if NoAnonymous file doesn't exist
        elif [ ! -f "$ANON_CONF_FILE" ]; then
            echo "yes" > "$ANON_CONF_FILE" || { echo "Error: Failed to create pure-ftpd NoAnonymous file." >&2; exit 1; }
        # Check if NoAnonymous file exists but doesn't contain 'yes'
        elif ! grep -q 'yes' "$ANON_CONF_FILE"; then
            echo "yes" > "$ANON_CONF_FILE" || { echo "Error: Failed to update pure-ftpd NoAnonymous file." >&2; exit 1; }
        fi
        
        # Restart pure-ftpd service. Pure-ftpd services can have different suffixes; try common ones.
        # Redirect stderr to /dev/null for individual restart attempts to keep output clean,
        # only report a collective failure if all attempts fail.
        systemctl restart pure-ftpd.service 2>/dev/null || \
        systemctl restart pure-ftpd-mysql.service 2>/dev/null || \
        systemctl restart pure-ftpd-ldap.service 2>/dev/null || \
        { echo "Error: Failed to restart pure-ftpd service. Please check pure-ftpd configuration and service status." >&2; exit 1; }
        FTP_SERVER_FIXED=true
    fi
fi

# --- Final Check ---

# If no FTP server was detected and fixed, provide a warning.
if ! "$FTP_SERVER_FIXED"; then
    echo "Warning: No common FTP server (vsftpd, proftpd, pure-ftpd) was detected or its configuration file found." >&2
    echo "The FTP service might be running via a different daemon or configuration not covered by this script." >&2
    echo "Please manually identify and configure your FTP server to disable anonymous access if the vulnerability persists." >&2
    exit 0 # Not a critical error if nothing was found to fix, but informs the user.
fi

exit 0 # Script finished successfully (and silently).
```