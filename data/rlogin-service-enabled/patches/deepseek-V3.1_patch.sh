```bash
#!/bin/bash
set -euo pipefail

# Root privilege check
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Function to disable rlogin service
disable_rlogin() {
    local service_files=("/etc/inetd.conf" "/etc/xinetd.d/rlogin" "/etc/xinetd.d/rsh")
    local i
    
    # Check and disable in inetd.conf if present
    if [ -f "/etc/inetd.conf" ]; then
        if grep -q "^rlogin" "/etc/inetd.conf"; then
            sed -i '/^rlogin/s/^/#/' "/etc/inetd.conf"
        fi
    fi
    
    # Check and disable rlogin/xinetd configuration files
    for i in "${service_files[@]}"; do
        if [ -f "$i" ]; then
            if grep -q "disable.*no" "$i" 2>/dev/null; then
                sed -i 's/disable.*no/disable = yes/' "$i"
            fi
            if grep -q "disable.*=.*no" "$i" 2>/dev/null; then
                sed -i 's/disable.*=.*no/disable = yes/' "$i"
            fi
        fi
    done
    
    # Kill running rlogin processes if any
    pkill -x "rlogind" 2>/dev/null || true
}

# Main execution
disable_rlogin

# Restart inetd/xinetd if found and running
if command -v inetd >/dev/null 2>&1 && systemctl is-active --quiet inetd 2>/dev/null; then
    systemctl restart inetd 2>/dev/null || true
fi

if command -v xinetd >/dev/null 2>&1 && systemctl is-active --quiet xinetd 2>/dev/null; then
    systemctl restart xinetd 2>/dev/null || true
fi

exit 0
```