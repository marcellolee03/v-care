```bash
#!/bin/bash
set -euo pipefail

# Mitigation for CVE-1999-0524 (ICMP Timestamp Reply Information Disclosure)
# This script disables the system's response to ICMP Type 13 (Timestamp Request)
# packets by inserting drop rules into the kernel's netfilter hooks.

# Verify root privileges
if [[ "${EUID}" -ne 0 ]]; then
    printf "Error: This script must be run as root.\n" >&2
    exit 1
fi

# Locate iptables binary
IPT=$(command -v iptables)

if [[ -x "${IPT}" ]]; then
    # Block incoming ICMP Timestamp Requests (Type 13)
    # Use -C to check for existence (idempotency) and -I to ensure it precedes broad ALLOW rules
    if ! "${IPT}" -C INPUT -p icmp --icmp-type 13 -j DROP 2>/dev/null; then
        "${IPT}" -I INPUT -p icmp --icmp-type 13 -j DROP
    fi

    # Block outgoing ICMP Timestamp Replies (Type 14) as defense-in-depth
    if ! "${IPT}" -C OUTPUT -p icmp --icmp-type 14 -j DROP 2>/dev/null; then
        "${IPT}" -I OUTPUT -p icmp --icmp-type 14 -j DROP
    fi
else
    printf "Error: iptables not found. Manual intervention required.\n" >&2
    exit 1
fi
```