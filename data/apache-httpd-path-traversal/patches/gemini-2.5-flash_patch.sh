```bash
#!/bin/bash
set -euo pipefail

# --- Constants ---
APACHE_CONF_DIR="/etc/apache2"
MITIGATION_CONF_BASENAME="cve-2021-41773-mitigation.conf"
MITIGATION_CONF_FILE="${APACHE_CONF_DIR}/conf-available/${MITIGATION_CONF_BASENAME}"
MITIGATION_CONF_SYMLINK="${APACHE_CONF_DIR}/conf-enabled/${MITIGATION_CONF_BASENAME}"
APACHE_SERVICE="apache2"

# --- Functions ---

# Function to check if running as root
check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        echo "Error: This script must be run as root." >&2
        exit 1
    fi
}

# Function to check if Apache service is active
check_apache_active() {
    if ! systemctl is-active --quiet "${APACHE_SERVICE}"; then
        echo "Error: Apache service ('${APACHE_SERVICE}') is not running or not found. Cannot restart." >&2
        exit 1
    fi
}

# Function to check if mod_rewrite is enabled
is_mod_rewrite_enabled() {
    # Check if the mod_rewrite symlink exists in mods-enabled
    [ -f "${APACHE_CONF_DIR}/mods-enabled/rewrite.load" ]
}

# Function to check if mitigation rules exist and are enabled
is_mitigation_active() {
    if [ -f "${MITIGATION_CONF_FILE}" ] && [ -L "${MITIGATION_CONF_SYMLINK}" ]; then
        # Check for the specific rewrite rules within the mitigation file
        grep -qE 'RewriteEngine On' "${MITIGATION_CONF_FILE}" && \
        grep -qE 'RewriteCond %{REQUEST_URI} "cgi-bin"' "${MITIGATION_CONF_FILE}" && \
        grep -qE 'RewriteRule "\(\?i\)\.\%\(2e\|2f\|5c\)" - \[F,L\]' "${MITIGATION_CONF_FILE}"
        return $?
    fi
    return 1
}

# --- Main Logic ---
check_root

if is_mitigation_active; then
    # Idempotent: Mitigation already applied
    exit 0
fi

# Enable mod_rewrite if not already enabled
if ! is_mod_rewrite_enabled; then
    a2enmod rewrite || { echo "Error: Failed to enable mod_rewrite. Check Apache installation." >&2; exit 1; }
fi

# Create or update the mitigation configuration file with specific rewrite rules
# These rules block requests to "cgi-bin" containing URL-encoded path traversal characters
# (.%2e for '.', .%2f for '/', .%5c for '\').
cat <<EOF > "${MITIGATION_CONF_FILE}"
# CVE-2021-41773 Mitigation: Apache HTTP Server 2.4.49 Directory Traversal / RCE
# This rule specifically targets the RCE vulnerability by forbidding
# requests to 'cgi-bin' that include URL-encoded path traversal characters
# like '.%2e/', '.%2f/', or '.%5c/'.
<IfModule mod_rewrite.c>
    RewriteEngine On
    # Conditions: Request URI contains "cgi-bin"
    RewriteCond %{REQUEST_URI} "cgi-bin"
    # Rule: Forbid if the URI contains a literal dot followed by URL-encoded
    #       dot (%2e), slash (%2f), or backslash (%5c) anywhere after "cgi-bin".
    #       (?i) makes the pattern case-insensitive.
    RewriteRule "(?i)\.\%(2e|2f|5c)" - [F,L]
</IfModule>
EOF
if [ ! -f "${MITIGATION_CONF_FILE}" ]; then
    echo "Error: Failed to create mitigation configuration file: ${MITIGATION_CONF_FILE}" >&2
    exit 1
fi

# Enable the new configuration file if not already enabled
if [ ! -L "${MITIGATION_CONF_SYMLINK}" ]; then
    a2enconf "$(basename "${MITIGATION_CONF_FILE}" .conf)" || { echo "Error: Failed to enable mitigation configuration. Check Apache installation." >&2; exit 1; }
fi

# Restart Apache to apply changes
check_apache_active # Ensure Apache is running before attempting to restart
systemctl restart "${APACHE_SERVICE}" || { echo "Error: Failed to restart Apache service." >&2; exit 1; }

# Final verification
if ! is_mitigation_active; then
    echo "Error: Mitigation appears to be incomplete or failed after Apache restart." >&2
    exit 1
fi

exit 0
```