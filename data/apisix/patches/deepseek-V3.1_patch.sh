```bash
#!/bin/bash
set -euo pipefail

# Strict error handling
trap 'echo "Error: Script failed at line $LINENO" >&2' ERR

# Verify root privileges
if [[ ${EUID} -ne 0 ]]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Variables
ETCD_VERSION_FILE="/etc/etcd/etcd.conf"
ETCD_SYSTEMD_UNIT="etcd.service"
VULNERABLE_VERSION="3.4.15"

# Function to verify etcd is installed and vulnerable
check_etcd_version() {
    if ! command -v etcd &>/dev/null; then
        echo "Error: etcd is not installed" >&2
        exit 0
    fi
    
    local installed_version
    if installed_version=$(etcd --version 2>/dev/null | grep -oP 'etcd Version: \K[0-9.]+'); then
        if [[ "${installed_version}" == "${VULNERABLE_VERSION}" ]]; then
            return 0
        fi
    fi
    return 1
}

# Function to disable etcd service
disable_etcd_service() {
    if systemctl is-active --quiet "${ETCD_SYSTEMD_UNIT}" 2>/dev/null; then
        systemctl stop "${ETCD_SYSTEMD_UNIT}"
        systemctl disable "${ETCD_SYSTEMD_UNIT}"
    fi
}

# Function to block port 2379
block_etcd_port() {
    local port="2379"
    local protocol="tcp"
    
    # Check if iptables is available
    if command -v iptables &>/dev/null; then
        # Add rule if not already present
        if ! iptables -C INPUT -p "${protocol}" --dport "${port}" -j DROP &>/dev/null; then
            iptables -A INPUT -p "${protocol}" --dport "${port}" -j DROP
        fi
    fi
}

# Main execution
main() {
    if ! check_etcd_version; then
        exit 0
    fi
    
    disable_etcd_service
    block_etcd_port
}

main "$@"
```