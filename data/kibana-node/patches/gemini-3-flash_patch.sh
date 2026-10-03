```bash
#!/bin/bash
set -euo pipefail

# Verify root privileges for system-level mitigation
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Root privileges required to mitigate CVE-2021-22940." >&2
    exit 1
fi

# Define target fixed version based on ESA-2021-24
FIXED_VERSION="7.14.1"

# Check if Kibana is installed via the native package manager
if rpm -q kibana >/dev/null 2>&1; then
    CURRENT_VERSION=$(rpm -q --queryformat '%{VERSION}' kibana)

    # Use version-sort to determine if the installed version is below the fixed threshold
    # If the first line of the sorted output is not the fixed version, current version is lower
    if [ "$(printf '%s\n%s' "$CURRENT_VERSION" "$FIXED_VERSION" | sort -V | head -n1)" != "$FIXED_VERSION" ]; then
        
        # Update the package to the fixed version or higher via yum
        # stdout is suppressed; stderr is preserved for error reporting
        yum update -y -q kibana >/dev/null

        # Restart the Kibana service to load the updated Node.js runtime
        if systemctl is-active --quiet kibana; then
            systemctl restart kibana >/dev/null 2>&1
        fi
    fi
fi
```