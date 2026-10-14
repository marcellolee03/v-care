```bash
#!/bin/bash

# CVE-2017-12617 Mitigation Script
# Targeted for Apache Tomcat on Debian GNU/Linux 9 (stretch)
# Ensures 'readonly' init-param is set to 'true' and removes uploaded artifacts.

set -euo pipefail

# Verify root privileges
if [[ "$EUID" -ne 0 ]]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# 1. Locate and patch web.xml files
# The vulnerability is exploited when 'readonly' is explicitly set to 'false'.
# We search for web.xml in common Tomcat paths and use sed to enforce 'true'.
TOMCAT_XML_FILES=$(find /etc/tomcat* /opt/tomcat* /var/lib/tomcat* /usr/share/tomcat* -name "web.xml" 2>/dev/null || true)

for config in $TOMCAT_XML_FILES; do
    if [[ -f "$config" ]]; then
        # Surgical replacement: find the line with 'readonly', then replace 'false' with 'true' in the following line.
        # This handles the standard Tomcat XML formatting.
        sed -i '/<param-name>readonly<\/param-name>/{n;s/<param-value>false<\/param-value>/<param-value>true<\/param-value>/;}' "$config"
    fi
done

# 2. Remove the specific JSP file identified by the scanner
# The vulnerability check successfully uploaded /openvasvt241992671.jsp
find /var/lib/tomcat*/webapps/ /opt/tomcat*/webapps/ -name "openvasvt241992671.jsp" -exec rm -f {} + 2>/dev/null || true

# 3. Restart Tomcat services to apply configuration changes
# Identifying services via systemctl
if command -v systemctl >/dev/null 2>&1; then
    TOMCAT_SERVICES=$(systemctl list-units --type=service --all | awk '/tomcat/ {print $1}' || true)
    for service in $TOMCAT_SERVICES; do
        systemctl restart "$service" 2>/dev/null || true
    done
fi

exit 0
```