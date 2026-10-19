```bash
#!/bin/bash
set -euo pipefail

# Check root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

TOMCAT_WEBAPPS="/var/lib/tomcat8/webapps"

# Check if Tomcat webapps directory exists
if [ ! -d "$TOMCAT_WEBAPPS" ]; then
    echo "Error: Tomcat webapps directory not found at $TOMCAT_WEBAPPS" >&2
    exit 1
fi

# Remove default example files and directories
rm -rf "${TOMCAT_WEBAPPS}/examples" 2>/dev/null || true
rm -rf "${TOMCAT_WEBAPPS}/docs" 2>/dev/null || true
rm -rf "${TOMCAT_WEBAPPS}/ROOT" 2>/dev/null || true
rm -rf "${TOMCAT_WEBAPPS}/host-manager" 2>/dev/null || true
rm -rf "${TOMCAT_WEBAPPS}/manager" 2>/dev/null || true

# Restart Tomcat to apply changes
systemctl restart tomcat8 2>/dev/null || true
```