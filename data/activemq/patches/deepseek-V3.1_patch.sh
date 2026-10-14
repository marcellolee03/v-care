```bash
#!/bin/bash
set -euo pipefail

# Verify root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

ACTIVEMQ_CONF_DIR="/etc/activemq"
ACTIVEMQ_CONF_FILE="${ACTIVEMQ_CONF_DIR}/jetty-realm.properties"

# Check if ActiveMQ configuration exists
if [ ! -d "${ACTIVEMQ_CONF_DIR}" ]; then
    echo "Error: ActiveMQ configuration directory not found: ${ACTIVEMQ_CONF_DIR}" >&2
    exit 1
fi

# Create backup of original configuration
if [ -f "${ACTIVEMQ_CONF_FILE}" ]; then
    cp "${ACTIVEMQ_CONF_FILE}" "${ACTIVEMQ_CONF_FILE}.bak.$(date +%Y%m%d%H%M%S)"
fi

# Remove default credentials from jetty-realm.properties
sed -i '/^admin:.*admin.*/d' "${ACTIVEMQ_CONF_FILE}" 2>/dev/null || true
sed -i '/^user:.*user.*/d' "${ACTIVEMQ_CONF_FILE}" 2>/dev/null || true

# Restart ActiveMQ service if running
if systemctl is-active --quiet activemq 2>/dev/null; then
    systemctl restart activemq
elif service activemq status >/dev/null 2>&1; then
    service activemq restart
fi

# Apply restrictive permissions to configuration
chmod 600 "${ACTIVEMQ_CONF_FILE}"
chown activemq:activemq "${ACTIVEMQ_CONF_FILE}" 2>/dev/null || true
```