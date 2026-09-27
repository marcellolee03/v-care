```bash
#!/bin/bash
set -euo pipefail

# Check root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Error: Root privileges required" >&2
    exit 1
fi

# Tomcat configurations path
TOMCAT_CONF_DIR="/etc/tomcat"
TOMCAT_SERVICE="tomcat"

# Stop Tomcat service
systemctl stop "$TOMCAT_SERVICE"

# Disable HTTP PUT method in web.xml
WEB_XML="${TOMCAT_CONF_DIR}/web.xml"
if [ -f "$WEB_XML" ]; then
    # Backup original configuration
    cp "$WEB_XML" "${WEB_XML}.bak_$(date +%Y%m%d_%H%M%S)"
    
    # Add security constraint to disable PUT method
    if ! grep -q "CVE-2017-12617" "$WEB_XML"; then
        sed -i '/<\/web-app>/i \
    <!-- CVE-2017-12617 Mitigation: Disable HTTP PUT method -->\
    <security-constraint>\
        <web-resource-collection>\
            <web-resource-name>Disable PUT</web-resource-name>\
            <url-pattern>/*</url-pattern>\
            <http-method>PUT</http-method>\
        </web-resource-collection>\
        <auth-constraint/>\
    </security-constraint>' "$WEB_XML"
    fi
fi

# Remove uploaded JSP file if it exists
UPLOADED_FILE="/openvasvt241992671.jsp"
if [ -f "$UPLOADED_FILE" ]; then
    rm -f "$UPLOADED_FILE"
fi

# Start Tomcat service
systemctl start "$TOMCAT_SERVICE"
```