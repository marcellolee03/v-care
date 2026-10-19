```bash
#!/bin/bash
set -euo pipefail

# Ensure the script is executed with root privileges
[[ "$(id -u)" -eq 0 ]] || { echo "Error: Root privileges required." >&2; exit 1; }

# Set non-interactive mode for apt-get
export DEBIAN_FRONTEND=noninteractive

# Update package index and upgrade bash to the latest patched version
# --only-upgrade ensures no new packages are installed
# Redirecting stdout to /dev/null ensures silence on success
apt-get update -qq > /dev/null
apt-get install -y -qq --only-upgrade bash > /dev/null

# Verify the fix by checking for the specific Shellshock exploit pattern in a subshell
# The exploit attempts to execute 'echo' during variable initialization
# A patched bash will ignore the function definition or handle it safely
VULN_CHECK=$(env 'x=() { :;}; echo vulnerable' bash -c "echo safe" 2>/dev/null || echo "safe")

if [[ "$VULN_CHECK" == *"vulnerable"* ]]; then
    echo "Error: Failed to mitigate Shellshock vulnerability." >&2
    exit 1
fi
```