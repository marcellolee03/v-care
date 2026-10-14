```bash
#!/bin/bash
# This script mitigates the "HTTP Debugging Methods (TRACE/TRACK) Enabled" vulnerability.
# It targets common web servers (Apache HTTP Server, Apache Tomcat, Nginx) on Debian 10.
# The script is designed to be minimalist, surgical, and idempotent,
# using only native commands available in the specified environment.

set -euo pipefail

# --- Basic Security Checks ---
# 1. Verify root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# Define the port from the vulnerability context
PORT_TO_CHECK="8080"

# --- Mitigation for Apache HTTP Server ---
# Configuration file and service name for Apache HTTP Server
APACHE_CONF="/etc/apache2/apache2.conf"
APACHE_SERVICE_NAME="apache2"
TRACE_DIRECTIVE="TraceEnable Off"

if [ -f "$APACHE_CONF" ]; then
    # Check if the TraceEnable Off directive is already present
    if ! grep -q "^[[:space:]]*${TRACE_DIRECTIVE}$" "$APACHE_CONF"; then
        echo "Adding '${TRACE_DIRECTIVE}' to '$APACHE_CONF' for Apache HTTP Server." >&2
        # Append the directive to the configuration file
        echo "$TRACE_DIRECTIVE" >> "$APACHE_CONF"
        
        # Restart Apache2 service if it's active to apply changes
        if systemctl is-active --quiet "$APACHE_SERVICE_NAME"; then
            echo "Restarting Apache2 service to apply changes." >&2
            systemctl restart "$APACHE_SERVICE_NAME" || { echo "Error: Failed to restart Apache2 service." >&2; exit 1; }
        else
            echo "Info: Apache2 service not active. Changes applied, but manual restart might be needed if it becomes active." >&2
        fi
    else
        echo "Info: '${TRACE_DIRECTIVE}' already present in '$APACHE_CONF'. No changes needed for Apache HTTP Server." >&2
    fi
else
    echo "Info: Apache configuration file '$APACHE_CONF' not found. Apache HTTP Server may not be installed." >&2
fi


# --- Mitigation for Apache Tomcat (assuming Debian 10 standard Tomcat 9 installation) ---
# Configuration file and service name for Apache Tomcat
TOMCAT_SERVICE_NAME="tomcat9"
TOMCAT_CONF_DIR="/etc/$TOMCAT_SERVICE_NAME" # Standard Debian package installation path
TOMCAT_SERVER_XML="${TOMCAT_CONF_DIR}/server.xml"

if [ -f "$TOMCAT_SERVER_XML" ]; then
    # Check if allowTrace="false" is already set for the connector on the specified port
    if grep -q "<Connector[^>]*port=\"${PORT_TO_CHECK}\"[^>]*allowTrace=\"false\"" "$TOMCAT_SERVER_XML"; then
        echo "Info: TRACE method already disabled for port $PORT_TO_CHECK in Tomcat's '$TOMCAT_SERVER_XML'. No changes needed." >&2
    else
        echo "Modifying '$TOMCAT_SERVER_XML' to disable TRACE method for port $PORT_TO_CHECK for Apache Tomcat." >&2
        
        # Use a temporary file for robust and atomic modifications
        TMP_SERVER_XML=$(mktemp)
        cp "$TOMCAT_SERVER_XML" "$TMP_SERVER_XML"

        # 1. First, replace allowTrace="true" with allowTrace="false" if it exists for the target connector.
        # This handles cases where allowTrace is already present but set to true.
        sed -i -E "s/(<Connector[^>]*port=\"${PORT_TO_CHECK}\"[^>]*)allowTrace=\"true\"/\1allowTrace=\"false\"/" "$TMP_SERVER_XML"
        
        # 2. If allowTrace attribute is still not present (i.e., it was not 'true'), add allowTrace="false".
        # This command appends ' allowTrace="false"' just before the closing '/>' or '>' of the Connector tag.
        if ! grep -q "<Connector[^>]*port=\"${PORT_TO_CHECK}\"[^>]*allowTrace=" "$TMP_SERVER_XML"; then
            sed -i -E "s/(<Connector[^>]*port=\"${PORT_TO_CHECK}\"[^>]*)(\/>|>[[:space:]]*)/\1 allowTrace=\"false\"\2/" "$TMP_SERVER_XML"
        fi
        
        # Compare original and temporary files to ensure actual changes were made before restarting
        if cmp -s "$TOMCAT_SERVER_XML" "$TMP_SERVER_XML"; then
            echo "Info: No actual changes were needed for Tomcat configuration (already correctly configured or target port connector not found). Skipping restart." >&2
            rm "$TMP_SERVER_XML"
        else
            mv "$TMP_SERVER_XML" "$TOMCAT_SERVER_XML"
            echo "Successfully updated '$TOMCAT_SERVER_XML'." >&2
            
            # Restart Tomcat service if it's active to apply changes
            if systemctl is-active --quiet "$TOMCAT_SERVICE_NAME"; then
                echo "Restarting Tomcat service ($TOMCAT_SERVICE_NAME) to apply changes." >&2
                systemctl restart "$TOMCAT_SERVICE_NAME" || { echo "Error: Failed to restart Tomcat service ($TOMCAT_SERVICE_NAME)." >&2; exit 1; }
            else
                echo "Info: Tomcat service ($TOMCAT_SERVICE_NAME) not active. Changes applied, but manual restart might be needed if it becomes active." >&2
            fi
        fi
    fi
else
    echo "Info: Tomcat server.xml file '$TOMCAT_SERVER_XML' not found. Apache Tomcat may not be installed or configured differently." >&2
fi


# --- Mitigation for Nginx ---
# Configuration file and service name for Nginx
NGINX_CONF="/etc/nginx/nginx.conf"
NGINX_SERVICE_NAME="nginx"
# Directive to block TRACE/TRACK methods at the Nginx level
TRACE_BLOCK_DIRECTIVE="    if (\$request_method ~* TRACE) { return 405; }"

if [ -f "$NGINX_CONF" ]; then
    # Check if the TRACE blocking directive already exists in the main config or included conf.d files
    if ! grep -qF "$TRACE_BLOCK_DIRECTIVE" "$NGINX_CONF" && ! grep -qF "if (\$request_method ~* TRACE)" /etc/nginx/conf.d/* 2>/dev/null; then
        echo "Adding TRACE/TRACK blocking directive to '$NGINX_CONF' http block for Nginx." >&2
        
        # Find the 'http {' block and insert the directive after it.
        # This ensures global application for all server blocks.
        # A backup of the Nginx config is made before modification for safety.
        cp "$NGINX_CONF" "${NGINX_CONF}.bak"
        sed -i "/^http {/a\\$TRACE_BLOCK_DIRECTIVE" "$NGINX_CONF"
        
        # Test Nginx configuration for syntax errors before attempting a restart
        if ! nginx -t &>/dev/null; then
            echo "Error: Nginx configuration test failed after modification. Reverting changes." >&2
            mv "${NGINX_CONF}.bak" "$NGINX_CONF"
            exit 1
        fi
        rm "${NGINX_CONF}.bak" # Remove backup if test passed
        
        # Restart Nginx service if it's active to apply changes
        if systemctl is-active --quiet "$NGINX_SERVICE_NAME"; then
            echo "Restarting Nginx service to apply changes." >&2
            systemctl restart "$NGINX_SERVICE_NAME" || { echo "Error: Failed to restart Nginx service." >&2; exit 1; }
        else
            echo "Info: Nginx service not active. Changes applied, but manual restart might be needed if it becomes active." >&2
        fi
    else
        echo "Info: TRACE/TRACK blocking directive already present for Nginx. No changes needed." >&2
    fi
else
    echo "Info: Nginx configuration file '$NGINX_CONF' not found. Nginx may not be installed." >&2
fi

exit 0
```