```bash
#!/bin/bash
set -euo pipefail

# Check for root privileges
if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# Locate Tomcat server.xml
TOMCAT_SERVICE_NAME="tomcat9" # Default for Debian 10
SERVER_XML=""

# Common paths for Tomcat's server.xml on Debian
if [ -f "/etc/$TOMCAT_SERVICE_NAME/server.xml" ]; then
    SERVER_XML="/etc/$TOMCAT_SERVICE_NAME/server.xml"
elif [ -f "/var/lib/$TOMCAT_SERVICE_NAME/conf/server.xml" ]; then
    SERVER_XML="/var/lib/$TOMCAT_SERVICE_NAME/conf/server.xml"
else
    echo "Error: Could not find Tomcat $TOMCAT_SERVICE_NAME server.xml. Please ensure Tomcat is installed or specify the path." >&2
    exit 1
fi

# Backup server.xml
cp "$SERVER_XML" "${SERVER_XML}.bak.$(date +%Y%m%d%H%M%S)" || \
    { echo "Error: Failed to backup $SERVER_XML." >&2; exit 1; }
echo "Info: Backup of $SERVER_XML created at ${SERVER_XML}.bak.$(date +%Y%m%d%H%M%S)" >&2

# --- Mitigation Steps ---

# 1. Configure HTTP Connector (port 8080) for redirection to HTTPS (port 8443)
# This makes Tomcat redirect to 8443 for requests that require a secure connection,
# typically defined by security constraints in web.xml.
if ! grep -q '<Connector port="8080".*redirectPort="8443"' "$SERVER_XML"; then
    if sed -i '/<Connector port="8080"/{ /redirectPort="8443"/! s/\(.*\)\( \/>\|>\)/\1 redirectPort="8443"\2/ }' "$SERVER_XML"; then
        echo "Info: Added redirectPort=\"8443\" to HTTP connector on port 8080 in $SERVER_XML." >&2
    else
        echo "Error: Failed to add redirectPort to HTTP connector in $SERVER_XML." >&2
        exit 1
    fi
fi

# 2. Enable HTTPS Connector (port 8443)
# Check if an active SSL connector for port 8443 already exists
if ! grep -qE '^[^<]*<Connector port="8443".*SSLEnabled="true"' "$SERVER_XML"; then
    echo "Info: HTTPS connector on port 8443 not found or not active. Attempting to enable/add." >&2

    # Check if a commented-out SSL connector for port 8443 exists and uncomment it
    # This sed command is designed to remove '<!--' and '-->' from lines within a block
    # that starts with '<!--' and ends with '-->', specifically if '<Connector port="8443"' is found within.
    if grep -qE '<!--.*<Connector port="8443".*SSLEnabled="true".*-->' "$SERVER_XML" || \
       grep -qE '^ *<!--$' "$SERVER_XML" && grep -qE '^ *-->$' "$SERVER_XML" && grep -qE '<Connector port="8443".*SSLEnabled="true"' "$SERVER_XML"; then
        if sed -i '/<!--/,/-->/{
            /<Connector port="8443"/{
                s/<!--//; s/-->//
            }
        }' "$SERVER_XML"; then
            echo "Info: Uncommented HTTPS connector on port 8443 in $SERVER_XML." >&2
        else
            echo "Error: Failed to uncomment HTTPS connector in $SERVER_XML." >&2
            exit 1
        fi
    else
        echo "Warning: No commented HTTPS connector found for port 8443 in $SERVER_XML. Adding a default SSL connector." >&2
        # If no commented connector is found, add a new one after the HTTP 8080 connector.
        # This ensures the required SSL functionality is available.
        AWK_SCRIPT=$(cat <<'EOF'
{ print }
/<Connector port="8080"/ {
    print "" # Add a blank line for readability
    print "    <!-- A default SSL/TLS HTTP/1.1 Connector for port 8443 - configured by hardening script -->"
    print "    <!-- IMPORTANT: Replace keystoreFile and keystorePass with your actual certificate details! -->"
    print "    <Connector port=\"8443\" protocol=\"org.apache.coyote.http11.Http11NioProtocol\""
    print "               maxThreads=\"150\" SSLEnabled=\"true\" scheme=\"https\" secure=\"true\""
    print "               clientAuth=\"false\" sslProtocol=\"TLSv1.2+TLSv1.3\""
    print "               keystoreFile=\"conf/tomcat.keystore\" keystorePass=\"changeit\" />"
}
EOF
)
        awk "$AWK_SCRIPT" "$SERVER_XML" > "${SERVER_XML}.tmp" && mv "${SERVER_XML}.tmp" "$SERVER_XML" || \
            { echo "Error: Failed to add new HTTPS connector to $SERVER_XML." >&2; exit 1; }
        echo "Info: Added a new default HTTPS connector to $SERVER_XML." >&2
    fi

    # Ensure SSLEnabled="true" for the 8443 connector
    if ! grep -q '<Connector port="8443".*SSLEnabled="true"' "$SERVER_XML"; then
        if sed -i '/<Connector port="8443"/{ /SSLEnabled="true"/! s/\(.*\)\( \/>\|>\)/\1 SSLEnabled="true"\2/ }' "$SERVER_XML"; then
            echo "Info: Ensured SSLEnabled=\"true\" for HTTPS connector on port 8443." >&2
        else
            echo "Error: Failed to set SSLEnabled=\"true\" for HTTPS connector." >&2
            exit 1
        fi
    fi

    # Ensure keystoreFile and keystorePass are set (with default placeholders if not present)
    if ! grep -q '<Connector port="8443".*keystoreFile=' "$SERVER_XML"; then
        if sed -i '/<Connector port="8443"/{ /keystoreFile=/! s/\(.*\)\( \/>\|>\)/\1 keystoreFile="conf\/tomcat.keystore"\2/ }' "$SERVER_XML"; then
            echo "Info: Set default keystoreFile for HTTPS connector." >&2
        else
            echo "Error: Failed to set keystoreFile for HTTPS connector." >&2
            exit 1
        fi
    fi
    if ! grep -q '<Connector port="8443".*keystorePass=' "$SERVER_XML"; then
        if sed -i '/<Connector port="8443"/{ /keystorePass=/! s/\(.*\)\( \/>\|>\)/\1 keystorePass="changeit"\2/ }' "$SERVER_XML"; then
            echo "Info: Set default keystorePass for HTTPS connector." >&2
        else
            echo "Error: Failed to set keystorePass for HTTPS connector." >&2
            exit 1
        fi
    fi

    {
        echo "Warning: The HTTPS connector on port 8443 has been enabled/configured." >&2
        echo "Crucially, the 'keystoreFile' and 'keystorePass' attributes are set to default placeholders." >&2
        echo "You MUST replace these with your actual SSL certificate keystore path and password for secure production use." >&2
        echo "Consult Tomcat documentation for proper SSL/TLS certificate configuration." >&2
    }
fi

# 3. Restart Tomcat service to apply changes
if systemctl is-active --quiet "$TOMCAT_SERVICE_NAME"; then
    echo "Info: Restarting $TOMCAT_SERVICE_NAME service..." >&2
    if systemctl restart "$TOMCAT_SERVICE_NAME"; then
        echo "Info: $TOMCAT_SERVICE_NAME service restarted successfully." >&2
    else
        echo "Error: Failed to restart $TOMCAT_SERVICE_NAME service. Please restart it manually." >&2
        exit 1
    fi
else
    echo "Warning: $TOMCAT_SERVICE_NAME service not found or not active. Please start/restart it manually to apply changes." >&2
fi

exit 0
```