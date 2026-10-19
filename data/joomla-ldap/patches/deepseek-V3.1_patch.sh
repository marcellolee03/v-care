```bash
#!/bin/bash

set -euo pipefail

# Verify root privileges
if [[ "${EUID}" -ne 0 ]]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Configuration variables
JOOMLA_BASE="/var/www/html"
JOOMLA_VERSION_FILE="${JOOMLA_BASE}/administrator/manifests/files/joomla.xml"
APACHE_CONFIG="/etc/apache2/sites-available/000-default.conf"

# Function to check if Joomla is installed
check_joomla_installed() {
    if [[ ! -f "${JOOMLA_VERSION_FILE}" ]]; then
        echo "Error: Joomla installation not found at ${JOOMLA_BASE}" >&2
        exit 1
    fi
}

# Function to get current Joomla version
get_joomla_version() {
    if [[ -f "${JOOMLA_VERSION_FILE}" ]]; then
        awk -F'[><]' '/<version>/ {print $3}' "${JOOMLA_VERSION_FILE}" 2>/dev/null || echo "0.0.0"
    else
        echo "0.0.0"
    fi
}

# Function to block vulnerable LDAP endpoint
block_ldap_endpoint() {
    # Create Apache configuration to block vulnerable LDAP endpoint
    if [[ -f "${APACHE_CONFIG}" ]]; then
        # Check if rule already exists
        if ! grep -q "location.*com_joomlaupdate" "${APACHE_CONFIG}"; then
            # Backup original configuration
            cp "${APACHE_CONFIG}" "${APACHE_CONFIG}.bak-$(date +%Y%m%d%H%M%S)"
            
            # Add location block to deny access to vulnerable component
            sed -i '/<\/VirtualHost>/i \
    # Block Joomla LDAP information disclosure vulnerability (CVE-2017-14596)\n    <Location "/administrator/components/com_joomlaupdate">\n        Require all denied\n    </Location>' "${APACHE_CONFIG}"
            
            # Reload Apache configuration
            systemctl reload apache2
        fi
    fi
}

# Function to set secure permissions
set_secure_permissions() {
    # Set restrictive permissions on Joomla directories
    find "${JOOMLA_BASE}" -type d -exec chmod 755 {} \;
    find "${JOOMLA_BASE}" -type f -exec chmod 644 {} \;
    
    # Protect configuration files
    if [[ -f "${JOOMLA_BASE}/configuration.php" ]]; then
        chmod 640 "${JOOMLA_BASE}/configuration.php"
        chown root:www-data "${JOOMLA_BASE}/configuration.php"
    fi
    
    # Protect administrator directory
    chmod 750 "${JOOMLA_BASE}/administrator"
}

# Main execution
main() {
    check_joomla_installed
    
    local current_version
    current_version=$(get_joomla_version)
    
    # Check if version is vulnerable (1.5.0 through 3.8.1)
    if [[ "${current_version}" == "0.0.0" ]] || \
       [[ "${current_version}" > "1.4.99" && "${current_version}" < "3.8.2" ]]; then
        
        block_ldap_endpoint
        set_secure_permissions
        
        # Clean up sensitive files
        find "${JOOMLA_BASE}" -name "*.log" -type f -exec rm -f {} \;
        find "${JOOMLA_BASE}" -name "error_log" -type f -exec rm -f {} \;
        
        # Clear Apache logs related to vulnerability
        if [[ -f "/var/log/apache2/access.log" ]]; then
            sed -i '/com_joomlaupdate/d' "/var/log/apache2/access.log" 2>/dev/null || true
        fi
    fi
}

# Execute main function
main
```