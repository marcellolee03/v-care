```bash
#!/bin/bash
# Minimalist, surgical, and idempotent BASH script to mitigate HttpOnly cookie vulnerability.
# Targets Apache Tomcat's context.xml configuration to enforce HttpOnly for session cookies.

set -euo pipefail

# Function to report errors to stderr and exit
err_exit() {
    echo "Error: $*" >&2
    exit 1
}

# 1. Verify root privileges
if [[ $EUID -ne 0 ]]; then
    err_exit "This script must be run as root."
fi

# 2. Define common Tomcat versions and their config/service names for Debian
# Order them by likelihood for Debian 9 (Stretch)
declare -a TOMCAT_VERSIONS=("tomcat8" "tomcat9")
CONTEXT_XML=""
TOMCAT_SERVICE=""
CHANGES_MADE=false

# 3. Find the active context.xml and corresponding Tomcat service
for version in "${TOMCAT_VERSIONS[@]}"; do
    # Prioritize /etc path for config files on Debian
    if [[ -f "/etc/${version}/context.xml" ]]; then
        CONTEXT_XML="/etc/${version}/context.xml"
        TOMCAT_SERVICE="${version}"
        break
    elif [[ -f "/var/lib/${version}/conf/context.xml" ]]; then
        CONTEXT_XML="/var/lib/${version}/conf/context.xml"
        TOMCAT_SERVICE="${version}"
        break
    fi
done

if [[ -z "$CONTEXT_XML" ]]; then
    err_exit "Could not find a Tomcat 'context.xml' file in common locations (/etc/tomcat*/context.xml or /var/lib/tomcat*/conf/context.xml). This script targets Apache Tomcat. Ensure Tomcat is installed and its configuration path is recognized."
fi

# 4. Apply mitigation to context.xml (idempotent logic)
# Check if "sessionCookieHttpOnly="true"" is already present in any <Context ...> tag
if grep -q -E '<Context[^>]*sessionCookieHttpOnly="true"' "$CONTEXT_XML"; then
    # Already mitigated, nothing to do. Exit silently.
    exit 0
fi

# Backup the original file before modifying
cp "$CONTEXT_XML" "${CONTEXT_XML}.bak" || err_exit "Failed to create backup of $CONTEXT_XML"

# Check if "sessionCookieHttpOnly="false"" is present, change it to "true"
if grep -q -E '<Context[^>]*sessionCookieHttpOnly="false"' "$CONTEXT_XML"; then
    # Use 's' command without 'g' to replace only the first occurrence if accidentally duplicated.
    sed -i -E '0,/<Context[^>]*>/s/(<Context[^>]*sessionCookieHttpOnly=")false"/\1true/' "$CONTEXT_XML" || err_exit "Failed to update sessionCookieHttpOnly from 'false' to 'true' in $CONTEXT_XML"
    CHANGES_MADE=true
elif grep -q -E '<Context' "$CONTEXT_XML"; then
    # If <Context> tag exists but sessionCookieHttpOnly is missing, add it.
    # Adds ' sessionCookieHttpOnly="true"' before the closing '>' of the first <Context> tag.
    # The '[^/]' part ensures it's not a self-closing tag like <Context />
    sed -i -E '0,/<Context[^>]*>/s/(<Context[^>]*[^/]?)>/\1 sessionCookieHttpOnly="true">/' "$CONTEXT_XML" || err_exit "Failed to add sessionCookieHttpOnly='true' to <Context> tag in $CONTEXT_XML"
    CHANGES_MADE=true
else
    # This case should ideally be caught by the file existence check, but included for robustness.
    err_exit "<Context> tag not found in $CONTEXT_XML. Cannot apply HttpOnly fix."
fi

# 5. Restart Tomcat service if changes were made
if [[ "$CHANGES_MADE" = true ]]; then
    if [[ -z "$TOMCAT_SERVICE" ]]; then
        err_exit "Tomcat service name could not be determined. Please restart Tomcat manually to apply changes made to $CONTEXT_XML."
    fi

    # Check if systemctl is available for systemd-based restart
    if command -v systemctl &>/dev/null; then
        systemctl restart "$TOMCAT_SERVICE" || err_exit "Failed to restart Tomcat service '$TOMCAT_SERVICE'. Please restart it manually."
    elif command -v service &>/dev/null; then
        # Fallback for older init systems if systemctl is not present (less likely for Debian 9 but good for robustness)
        service "$TOMCAT_SERVICE" restart || err_exit "Failed to restart Tomcat service '$TOMCAT_SERVICE' using 'service' command. Please restart it manually."
    else
        err_exit "Neither 'systemctl' nor 'service' commands found. Cannot restart Tomcat service '$TOMCAT_SERVICE'. Please restart it manually to apply changes."
    fi
fi

# Script exits silently on success.
exit 0
```