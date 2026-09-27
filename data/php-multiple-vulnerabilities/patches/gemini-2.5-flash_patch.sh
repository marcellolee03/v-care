```bash
#!/bin/bash
set -euo pipefail

# Role: Senior System Security Engineer and Linux Hardening Specialist.
# Task: Mitigate CVE-2012-1823 (PHP-CGI query string arbitrary option vulnerability)
#       on Debian 8 with Apache HTTP Server by blocking the '-d' query parameter.

# --- Configuration Variables ---
APACHE_CONFIG_DIR="/etc/apache2"
APACHE_SITES_ENABLED_DIR="$APACHE_CONFIG_DIR/sites-enabled"
APACHE_RESTART_COMMAND="service apache2 restart"
APACHE_CONFIGTEST_COMMAND="apache2ctl -t"
MITIGATION_COMMENT="# CVE-2012-1823 mitigation: Block -d in query string for PHP-CGI"
VIRTUALHOST_PORT="8080" # Target port for the vulnerable service

# Indentation for the rules to fit within Apache config files
INDENT="        " # 8 spaces, common for VirtualHost content

# Prepare the rules for sed insertion, escaping newlines and applying indentation
# This block prevents PHP-CGI from parsing command-line options via the query string.
# It specifically targets the '-d' option, which can be abused to set INI directives
# like 'allow_url_include' at runtime, leading to arbitrary code execution.
# The regex "(^|&)-d[+=]" matches '-d' at the beginning of the query string or
# after an '&', followed by '+' or '=' (e.g., -d+option or -d=option).
INSERT_RULES_ESCAPED="${INDENT}${MITIGATION_COMMENT}"
INSERT_RULES_ESCAPED+="\\n${INDENT}<IfModule mod_rewrite.c>"
INSERT_RULES_ESCAPED+="\\n${INDENT}    RewriteEngine On"
INSERT_RULES_ESCAPED+="\\n${INDENT}    RewriteCond %{QUERY_STRING} \"(^|&)-d[+=]\" [NC]"
INSERT_RULES_ESCAPED+="\\n${INDENT}    RewriteRule .* - [F,L]" # Forbid and Last rule
INSERT_RULES_ESCAPED+="\\n${INDENT}</IfModule>"

# --- Script Logic ---

# 1. Verify root privileges
if [[ $(id -u) -ne 0 ]]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# 2. Check for Apache HTTP Server installation
if [[ ! -d "$APACHE_CONFIG_DIR" ]]; then
    echo "Error: Apache configuration directory not found at '$APACHE_CONFIG_DIR'." >&2
    echo "This script assumes Apache HTTP Server is the web server." >&2
    exit 1
fi

# 3. Locate the Apache VirtualHost configuration file for the vulnerable port
# Searches for files under sites-enabled that contain a VirtualHost directive for the specified port.
SITE_CONFIG=$(grep -lR "<VirtualHost *:$VIRTUALHOST_PORT>" "$APACHE_SITES_ENABLED_DIR" 2>/dev/null | head -n 1)

if [[ -z "$SITE_CONFIG" ]]; then
    echo "Error: Could not find an Apache VirtualHost configuration listening on port $VIRTUALHOST_PORT in '$APACHE_SITES_ENABLED_DIR'." >&2
    echo "Please verify the web server configuration or adjust the script's VIRTUALHOST_PORT variable." >&2
    exit 1
fi

# 4. Check for idempotence: determine if mitigation rules are already in place
if grep -qF "$MITIGATION_COMMENT" "$SITE_CONFIG"; then
    # Script is silent on success, including when no action is needed due to idempotency.
    exit 0
fi

# 5. Create a backup of the target configuration file before modification
cp "$SITE_CONFIG" "${SITE_CONFIG}.bak" || {
    echo "Error: Failed to create a backup of '$SITE_CONFIG'." >&2
    exit 1
}

# 6. Apply the mitigation rules to the Apache VirtualHost configuration
# Rules are inserted just before the closing </VirtualHost> tag.
# If 'mod_rewrite' is not enabled, these rules will be ignored by Apache.
# Enabling 'mod_rewrite' (e.g., 'a2enmod rewrite') is outside the scope of this minimalist script.
if ! sed -i "/<\/VirtualHost>/i$INSERT_RULES_ESCAPED" "$SITE_CONFIG"; then
    echo "Error: Failed to apply mitigation rules to '$SITE_CONFIG'." >&2
    # Attempt to restore from backup on failure
    mv "${SITE_CONFIG}.bak" "$SITE_CONFIG" 2>/dev/null || echo "Error: Failed to restore backup for '$SITE_CONFIG'." >&2
    exit 1
fi

# 7. Test Apache configuration syntax
if ! $APACHE_CONFIGTEST_COMMAND; then
    echo "Error: Apache configuration test failed after applying mitigation rules to '$SITE_CONFIG'." >&2
    echo "Please review the Apache error logs for details. Attempting to restore original configuration." >&2
    mv "${SITE_CONFIG}.bak" "$SITE_CONFIG" 2>/dev/null || echo "Error: Failed to restore backup for '$SITE_CONFIG'." >&2
    exit 1
fi

# 8. Restart Apache service to apply the new configuration
if ! $APACHE_RESTART_COMMAND; then
    echo "Error: Failed to restart Apache service after applying mitigation rules to '$SITE_CONFIG'." >&2
    echo "Please check Apache service status. Attempting to restore original configuration." >&2
    mv "${SITE_CONFIG}.bak" "$SITE_CONFIG" 2>/dev/null || echo "Error: Failed to restore backup for '$SITE_CONFIG'." >&2
    exit 1
fi

# Script exits silently on successful application or if already mitigated.
# The backup file remains for potential rollback.
```