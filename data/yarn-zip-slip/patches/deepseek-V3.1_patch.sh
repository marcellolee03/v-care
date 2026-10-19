```bash
#!/bin/bash
set -euo pipefail

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Define Hadoop service name and configuration directory
HADOOP_SERVICE="hadoop-yarn-resourcemanager"
HADOOP_CONF_DIR="/etc/hadoop"

# Check if Hadoop is installed and running
if ! systemctl is-active --quiet "$HADOOP_SERVICE" 2>/dev/null; then
    echo "Error: Hadoop YARN ResourceManager service is not running" >&2
    exit 1
fi

# Create backup of core-site.xml if it exists
if [ -f "${HADOOP_CONF_DIR}/core-site.xml" ]; then
    cp "${HADOOP_CONF_DIR}/core-site.xml" "${HADOOP_CONF_DIR}/core-site.xml.backup.$(date +%Y%m%d)"
fi

# Add security property to prevent Zip Slip vulnerability
if [ -f "${HADOOP_CONF_DIR}/core-site.xml" ]; then
    if ! grep -q "hadoop.security.allow.zip.slip" "${HADOOP_CONF_DIR}/core-site.xml"; then
        sed -i '/<\/configuration>/i \
  <property>\
    <name>hadoop.security.allow.zip.slip</name>\
    <value>false</value>\
    <description>Prevent Zip Slip vulnerability by disabling extraction outside target directory</description>\
  </property>' "${HADOOP_CONF_DIR}/core-site.xml"
    fi
fi

# Restart Hadoop service to apply changes
systemctl restart "$HADOOP_SERVICE"

# Verify service restarted successfully
if ! systemctl is-active --quiet "$HADOOP_SERVICE"; then
    echo "Error: Failed to restart Hadoop service" >&2
    exit 1
fi
```