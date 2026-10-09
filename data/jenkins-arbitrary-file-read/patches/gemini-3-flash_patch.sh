```bash
#!/bin/bash

# CVE-2021-21615 Mitigation Script
# Jenkins Arbitrary File Read Vulnerability
# Version: 1.0
# Logic: Performs a surgical upgrade to a non-vulnerable version via the package manager.

set -euo pipefail

# Ensure the script is executed with root privileges
if [ "$EUID" -ne 0 ]; then
    exit 1
fi

# Define the threshold version for mitigation
# CVE-2021-21615 is fixed in 2.276 and 2.263.3 (LTS)
FIX_VER="2.276"

# Check if Jenkins is installed and retrieve the version
# Uses dpkg-query as the environment is Debian 9
CUR_VER=$(dpkg-query -W -f='${Version}' jenkins 2>/dev/null | cut -d':' -f2 | cut -d'-' -f1) || exit 0

# Idempotency check: Only proceed if current version is less than the fixed version
if [ -n "$CUR_VER" ] && dpkg --compare-versions "$CUR_VER" lt "$FIX_VER"; then
    
    # Configure environment for non-interactive package management
    export DEBIAN_FRONTEND=noninteractive

    # Update metadata and upgrade only the Jenkins package
    # Redirecting stdout to /dev/null to remain silent on success
    apt-get update -qq > /dev/null
    apt-get install -y -qq --only-upgrade jenkins > /dev/null

    # Restart the service to ensure the patched .war file is loaded into memory
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart jenkins > /dev/null 2>&1
    elif [ -f /etc/init.d/jenkins ]; then
        /etc/init.d/jenkins restart > /dev/null 2>&1
    fi
fi
```