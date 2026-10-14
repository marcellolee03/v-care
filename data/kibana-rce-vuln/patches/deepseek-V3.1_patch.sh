```bash
#!/bin/bash
set -euo pipefail

# Script: Mitigate CVE-2019-7609 (Kibana RCE via Timelion)
# Target: CentOS 7 with Kibana < 5.6.15 or < 6.6.1

# Verify root privileges
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Variables
KIBANA_SERVICE="kibana"
TIMELION_CONFIG_DIR="/etc/kibana"
TIMELION_CONFIG_FILE="${TIMELION_CONFIG_DIR}/timelion.json"
BACKUP_SUFFIX=".backup-$(date +%Y%m%d-%H%M%S)"

# Function: Check if Kibana service exists and is active
check_kibana_service() {
    if systemctl list-unit-files | grep -q "^${KIBANA_SERVICE}.service"; then
        if systemctl is-active --quiet "${KIBANA_SERVICE}"; then
            echo "Warning: Kibana service is running" >&2
            return 0
        fi
    fi
    return 1
}

# Function: Disable Timelion visualizer via configuration
disable_timelion() {
    local config_file="$1"
    
    # Create backup before modification
    if [[ -f "$config_file" ]]; then
        cp -p "${config_file}" "${config_file}${BACKUP_SUFFIX}"
    fi
    
    # Create/overwrite config to disable Timelion
    cat > "$config_file" << 'EOF'
{
  "timelion:enabled": false
}
EOF
    
    # Set appropriate permissions
    chown kibana:kibana "$config_file"
    chmod 644 "$config_file"
}

# Main execution
main() {
    # Step 1: Stop Kibana service if running
    if check_kibana_service; then
        systemctl stop "$KIBANA_SERVICE"
        trap 'systemctl start "$KIBANA_SERVICE"' EXIT
    fi
    
    # Step 2: Ensure config directory exists
    if [[ ! -d "$TIMELION_CONFIG_DIR" ]]; then
        mkdir -p "$TIMELION_CONFIG_DIR"
        chown kibana:kibana "$TIMELION_CONFIG_DIR"
        chmod 755 "$TIMELION_CONFIG_DIR"
    fi
    
    # Step 3: Apply mitigation by disabling Timelion
    disable_timelion "$TIMELION_CONFIG_FILE"
    
    # Step 4: Verify mitigation
    if [[ -f "$TIMELION_CONFIG_FILE" ]] && \
       grep -q '"timelion:enabled": false' "$TIMELION_CONFIG_FILE"; then
        # Success - exit silently
        exit 0
    else
        echo "Error: Failed to apply mitigation" >&2
        exit 1
    fi
}

# Execute main function
main
```