```bash
#!/bin/bash
#
# MITIGATION SCRIPT FOR CVE-2017-1000028
# Oracle GlassFish Server <= 4.1.1 Directory Traversal Vulnerability
#
# This script applies a network-level mitigation by blocking all incoming TCP
# traffic to port 4848, which is the port identified as vulnerable for GlassFish
# Server directory traversal. This prevents external exploitation of the
# vulnerability by denying access to the vulnerable service.
#
# IMPORTANT: This is a network-level mitigation. The underlying vulnerability
# in GlassFish Server remains. A proper long-term fix involves upgrading
# GlassFish to a non-vulnerable version (e.g., 4.1.2 or later) or removing
# the service if no longer needed.
#
# Persistence: The iptables rule added by this script is temporary and will
# not persist across reboots by default. To make the rule permanent, you
# must save your iptables configuration after running this script (e.g.,
# using 'netfilter-persistent save' or 'iptables-save > /etc/iptables/rules.v4').
#
set -euo pipefail

# --- Pre-checks ---

# Verify root privileges
if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: This script must be run as root." >&2
    exit 1
fi

# Verify 'iptables' command availability
if ! command -v iptables &> /dev/null; then
    echo "ERROR: 'iptables' command not found. Please ensure iptables is installed and in the PATH." >&2
    exit 1
fi

# --- Mitigation Logic ---

# Define the vulnerable port
VULNERABLE_PORT="4848"

# Check if the iptables rule to drop traffic to the vulnerable port already exists.
# `iptables -C` returns exit code 0 if the rule exists, 1 if it does not.
if iptables -C INPUT -p tcp --dport "${VULNERABLE_PORT}" -j DROP &> /dev/null; then
    # Rule already exists, no action needed (idempotent success)
    :
else
    # Rule does not exist, add it to the INPUT chain to drop incoming TCP traffic
    # to the specified port.
    if ! iptables -A INPUT -p tcp --dport "${VULNERABLE_PORT}" -j DROP; then
        echo "ERROR: Failed to add iptables rule to block port ${VULNERABLE_PORT}." >&2
        exit 1
    fi
fi

# Script completes silently on success (rule was added or already existed).
exit 0
```