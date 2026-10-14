```bash
#!/bin/bash
set -euo pipefail

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# Determine Tomcat server.xml path
TOMCAT_SERVER_XML=""
if [ -f "/etc/tomcat9/server.xml" ]; then
    TOMCAT_SERVER_XML="/etc/tomcat9/server.xml"
elif [ -f "/etc/tomcat8/server.xml" ]; then
    TOMCAT_SERVER_XML="/etc/tomcat8/server.xml"
else
    echo "Error: Could not find Tomcat server.xml configuration file (checked /etc/tomcat9/server.xml and /etc/tomcat8/server.xml)." >&2
    exit 1
fi

MITIGATION_APPLIED=false

# Check if the AJP connector on port 8009 is present and not already commented out.
# This grep looks for a line containing the AJP connector configuration.
# The second grep ensures that the found line is NOT already commented out (i.e., does not start with '<!--').
if grep -qE '<Connector\s*port="8009"\s*protocol="AJP/1.3"' "$TOMCAT_SERVER_XML" && \
   ! grep -qE '^\s*<!--\s*<Connector\s*port="8009"\s*protocol="AJP/1.3"' "$TOMCAT_SERVER_XML"; then

    # Comment out the AJP connector line in server.xml.
    # The sed command captures the entire line containing the AJP connector
    # (including leading/trailing whitespace with \s*) and wraps it in XML comments.
    sed -i '/<Connector\s*port="8009"\s*protocol="AJP\/1.3"/s/^\(\s*<Connector.*AJP\/1\.3.*\)\s*$/<!--\1-->/' "$TOMCAT_SERVER_XML"
    MITIGATION_APPLIED=true
fi

# If mitigation was applied (AJP connector was commented out), restart the Tomcat service.
if [ "$MITIGATION_APPLIED" = true ]; then
    TOMCAT_SERVICE=""
    # Attempt to determine the correct Tomcat service name for systemd.
    if systemctl list-unit-files --type=service | grep -q "tomcat9.service"; then
        TOMCAT_SERVICE="tomcat9"
    elif systemctl list-unit-files --type=service | grep -q "tomcat8.service"; then
        TOMCAT_SERVICE="tomcat8"
    fi

    if [ -z "$TOMCAT_SERVICE" ]; then
        echo "Error: Neither tomcat9 nor tomcat8 systemd service found. Manual Tomcat restart is required for changes to take effect." >&2
        exit 1
    fi

    # Restart the identified Tomcat service.
    systemctl restart "$TOMCAT_SERVICE" || { echo "Error: Failed to restart $TOMCAT_SERVICE service. Manual restart required." >&2; exit 1; }
fi

# Script exits silently on success, as per requirements.
```