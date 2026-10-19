```bash
#!/bin/bash
set -euo pipefail

# Check root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Error: Root privileges required" >&2
    exit 1
fi

# Disable ICMP timestamp responses by setting sysctl parameter
echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_all

# Verify the change was applied
if [ "$(cat /proc/sys/net/ipv4/icmp_echo_ignore_all)" -ne 1 ]; then
    echo "Error: Failed to disable ICMP responses" >&2
    exit 1
fi
```