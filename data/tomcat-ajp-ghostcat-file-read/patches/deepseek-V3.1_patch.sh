```bash
#!/bin/bash
set -euo pipefail

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Apache Tomcat configuration file locations
CONFIG_DIRS=(
    "/etc/tomcat*"
    "/usr/share/tomcat*/conf"
    "/var/lib/tomcat*/conf"
    "/opt/tomcat*/conf"
)

# Find and disable AJP connector in server.xml files
find "${CONFIG_DIRS[@]}" -name "server.xml" 2>/dev/null | while read -r config_file; do
    # Create backup if not already done
    if [ ! -f "${config_file}.bak" ]; then
        cp "$config_file" "${config_file}.bak"
    fi
    
    # Check if AJP connector is enabled and disable it by commenting it out
    if grep -q "protocol=\"AJP/" "$config_file"; then
        sed -i '/protocol="AJP\/1.3"/s/^/<!-- /; /protocol="AJP\/1.3"/s/$/ -->/' "$config_file"
    fi
done

# If no server.xml found, check for AJP service files
AJP_SERVICE_FILES=(
    "/etc/systemd/system/*ajp*"
    "/lib/systemd/system/*ajp*"
)

# Disable any AJP-related systemd services
find "${AJP_SERVICE_FILES[@]}" -name "*.service" 2>/dev/null | while read -r service_file; do
    service_name=$(basename "$service_file")
    systemctl stop "$service_name" 2>/dev/null || true
    systemctl disable "$service_name" 2>/dev/null || true
done

# Verify port 8009 is not listening
if ss -tln | grep -q ':8009'; then
    echo "Warning: Port 8009 is still listening. Manual intervention may be required." >&2
fi
```