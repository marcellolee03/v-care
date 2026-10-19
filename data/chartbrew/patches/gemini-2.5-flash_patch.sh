```bash
#!/bin/bash
set -euo pipefail

# --- Configuration ---
readonly VULNERABLE_PORT=3000
readonly NFT_RULES_DIR="/etc/nftables/conf.d"
readonly NFT_RULE_FILE="${NFT_RULES_DIR}/99-block-port-${VULNERABLE_PORT}-http.nft"
readonly NFT_RULE_COMMENT="VULN_MITIGATION_PORT_${VULNERABLE_PORT}"

# --- Functions ---

# check_root: Verifies that the script is executed with root privileges.
check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        echo "Error: This script must be run as root." >&2
        exit 1
    fi
}

# command_exists: Checks if a given command is available in the system's PATH.
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# --- Main Script ---

check_root

# Ensure 'nft' command (from nftables) is available.
if ! command_exists nft; then
    echo "Error: 'nft' command not found. nftables is required for this mitigation." >&2
    echo "Please ensure nftables is installed and available on your Debian 12 system." >&2
    exit 1
fi

# Ensure 'systemctl' command (from systemd) is available for service management.
if ! command_exists systemctl; then
    echo "Error: 'systemctl' command not found. systemd is required for nftables service management." >&2
    exit 1
fi

# Idempotence Check: Verify if the mitigation rule is already active in the nftables ruleset.
if nft list ruleset | grep -q "${NFT_RULE_COMMENT}"; then
    # Rule already active, no action needed.
    exit 0
fi

# Create the nftables configuration directory if it does not exist.
if [[ ! -d "${NFT_RULES_DIR}" ]]; then
    mkdir -p "${NFT_RULES_DIR}" || { echo "Error: Failed to create directory ${NFT_RULES_DIR}" >&2; exit 1; }
fi

# Write the nftables rule to a new file in the conf.d directory.
# This rule blocks all incoming TCP traffic to the vulnerable port,
# effectively preventing cleartext transmission of sensitive information over HTTP on this port.
# This file will be automatically loaded by nftables.service because /etc/nftables.conf
# typically includes configuration files from /etc/nftables/conf.d/.
cat <<EOF > "${NFT_RULE_FILE}" || { echo "Error: Failed to write nftables rule file ${NFT_RULE_FILE}" >&2; exit 1; }
# Mitigation for Cleartext Transmission of Sensitive Information via HTTP on port ${VULNERABLE_PORT}
# CVE Context: http://fedora:3000/login:password
# Action: Drop all incoming TCP traffic to port ${VULNERABLE_PORT} to prevent cleartext data transmission.
# Created by security script on $(date +"%Y-%m-%d %H:%M:%S").

table inet filter {
    chain input {
        # This rule ensures cleartext HTTP traffic to the vulnerable port is dropped.
        tcp dport ${VULNERABLE_PORT} drop comment "${NFT_RULE_COMMENT}"
    }
}
EOF

# Reload nftables to apply the new rule.
if ! systemctl reload nftables; then
    echo "Error: Failed to reload nftables service. The rule might not be active." >&2
    echo "Please check 'systemctl status nftables.service' and 'nft list ruleset' manually." >&2
    # Attempt to remove the partially created file for cleanup in case of reload failure.
    rm -f "${NFT_RULE_FILE}" || true
    exit 1
fi

# Script exits silently on success.
```