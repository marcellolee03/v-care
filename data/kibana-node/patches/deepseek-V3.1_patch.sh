```bash
#!/bin/bash
set -euo pipefail

# Root privilege verification
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Global variables
KIBANA_USER="kibana"
KIBANA_GROUP="kibana"
KIBANA_PORT=5601
KIBANA_PATHS=(
    "/usr/share/kibana"
    "/opt/kibana"
    "/var/lib/kibana"
)

# Function to check if Kibana process is running
is_kibana_running() {
    if pgrep -f "node.*kibana" > /dev/null 2>&1 || \
       ss -tlnp | grep -q ":${KIBANA_PORT} "; then
        return 0
    fi
    return 1
}

# Function to stop Kibana service
stop_kibana_service() {
    if is_kibana_running; then
        echo "Stopping Kibana service..." >&2
        pkill -f "node.*kibana" 2>/dev/null || true
        sleep 2
        
        # Double-check and force kill if necessary
        if is_kibana_running; then
            pkill -9 -f "node.*kibana" 2>/dev/null || true
            sleep 1
        fi
    fi
}

# Function to apply security hardening
apply_security_hardening() {
    local found_path=""
    
    # Find Kibana installation path
    for path in "${KIBANA_PATHS[@]}"; do
        if [[ -d "$path" ]]; then
            found_path="$path"
            break
        fi
    done
    
    if [[ -z "$found_path" ]]; then
        echo "Error: Kibana installation not found in known paths" >&2
        exit 1
    fi
    
    echo "Found Kibana at: $found_path" >&2
    
    # 1. Remove world-writable permissions from Kibana directories
    find "$found_path" -type d -perm /o=w -exec chmod o-w {} \; 2>/dev/null || true
    
    # 2. Remove world-writable permissions from Kibana files
    find "$found_path" -type f -perm /o=w -exec chmod o-w {} \; 2>/dev/null || true
    
    # 3. Ensure proper ownership on all Kibana files
    chown -R ${KIBANA_USER}:${KIBANA_GROUP} "$found_path" 2>/dev/null || true
    
    # 4. Remove setuid/setgid bits from Node.js binaries if present
    find "$found_path" -type f \( -name "node" -o -name "nodejs" \) \
        -exec chmod u-s,g-s {} \; 2>/dev/null || true
    
    # 5. Restrict access to Kibana configuration files
    find "$found_path" -name "*.yml" -o -name "*.yaml" -o -name "*.conf" \
        -o -name "*.json" | while read -r config_file; do
        chmod 640 "$config_file" 2>/dev/null || true
    done
    
    # 6. Apply firewall rule to restrict Kibana port access
    if command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --remove-port=${KIBANA_PORT}/tcp 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
    fi
    
    # 7. Create security wrapper script if Node.js is bundled
    local node_path=$(find "$found_path" -type f -name "node" -executable 2>/dev/null | head -1)
    if [[ -n "$node_path" ]]; then
        local wrapper_dir="/usr/local/bin"
        local wrapper_script="${wrapper_dir}/kibana-secure"
        
        cat > "$wrapper_script" << 'EOF'
#!/bin/bash
# Security wrapper for Kibana Node.js
export NODE_OPTIONS="--no-experimental-fetch \
                     --disable-proto=delete \
                     --no-wasm \
                     --no-addons"
exec "$@"
EOF
        
        chmod 755 "$wrapper_script"
        chown root:root "$wrapper_script"
    fi
}

# Main execution
main() {
    echo "Applying Kibana security hardening..." >&2
    
    stop_kibana_service
    apply_security_hardening
    
    echo "Security hardening completed successfully" >&2
    exit 0
}

# Execute main function
main
```