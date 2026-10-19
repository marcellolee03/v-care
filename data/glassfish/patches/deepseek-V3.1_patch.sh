```bash
#!/bin/bash
set -euo pipefail

# Verify root privileges
if [[ ${EUID} -ne 0 ]]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Define GlassFish configuration file location
GLASSFISH_DOMAIN_DIR="/opt/glassfish4/glassfish/domains/domain1"
ASENV_FILE="${GLASSFISH_DOMAIN_DIR}/config/asenv.conf"
DOMAIN_XML="${GLASSFISH_DOMAIN_DIR}/config/domain.xml"
ADMIN_SERVICE_CONFIG="${GLASSFISH_DOMAIN_DIR}/config/admin-service-config.xml"

# Check if GlassFish installation exists
if [[ ! -d "${GLASSFISH_DOMAIN_DIR}" ]]; then
    echo "Error: GlassFish domain directory not found at ${GLASSFISH_DOMAIN_DIR}" >&2
    exit 1
fi

# Function to restart GlassFish domain
restart_glassfish_domain() {
    local domain_path="$1"
    
    # Check if asadmin exists
    if [[ -f "${domain_path}/../../bin/asadmin" ]]; then
        "${domain_path}/../../bin/asadmin" stop-domain domain1 >/dev/null 2>&1 || true
        sleep 2
        "${domain_path}/../../bin/asadmin" start-domain domain1 >/dev/null 2>&1 &
    fi
}

# Apply security hardening measures

# 1. Disable directory traversal by securing admin console access
if [[ -f "${DOMAIN_XML}" ]]; then
    # Backup original configuration
    cp "${DOMAIN_XML}" "${DOMAIN_XML}.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    
    # Ensure secure admin access settings
    if grep -q "<secure-admin>false</secure-admin>" "${DOMAIN_XML}"; then
        sed -i 's|<secure-admin>false</secure-admin>|<secure-admin>true</secure-admin>|g' "${DOMAIN_XML}"
    fi
fi

# 2. Restrict admin console to localhost only
if [[ -f "${ADMIN_SERVICE_CONFIG}" ]]; then
    # Backup
    cp "${ADMIN_SERVICE_CONFIG}" "${ADMIN_SERVICE_CONFIG}.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    
    # Update network listeners to localhost only
    sed -i 's/address="0.0.0.0"/address="127.0.0.1"/g' "${ADMIN_SERVICE_CONFIG}" 2>/dev/null || true
fi

# 3. Apply security patch workaround: Remove or secure vulnerable endpoint access
# Create security constraint in web.xml if it exists
WEB_XML="${GLASSFISH_DOMAIN_DIR}/applications/__admingui/WEB-INF/web.xml"
if [[ -f "${WEB_XML}" ]]; then
    # Backup
    cp "${WEB_XML}" "${WEB_XML}.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    
    # Add security constraint for META-INF directory access
    if ! grep -q "META-INF" "${WEB_XML}"; then
        # Insert security constraint before closing web-app tag
        sed -i '/<\/web-app>/i\
  <security-constraint>\
    <web-resource-collection>\
      <web-resource-name>Restricted META-INF</web-resource-name>\
      <url-pattern>/theme/META-INF/*</url-pattern>\
    </web-resource-collection>\
    <auth-constraint/>\
  </security-constraint>' "${WEB_XML}" 2>/dev/null || true
    fi
fi

# 4. Ensure proper file permissions on GlassFish directories
find "${GLASSFISH_DOMAIN_DIR}" -type f -name "*.xml" -exec chmod 640 {} \; 2>/dev/null || true
find "${GLASSFISH_DOMAIN_DIR}" -type d -exec chmod 750 {} \; 2>/dev/null || true

# Restart GlassFish domain to apply changes
restart_glassfish_domain "${GLASSFISH_DOMAIN_DIR}"

exit 0
```