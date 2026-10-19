```bash
#!/bin/bash
set -euo pipefail

# Ensure the script is executed with root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# CVE-2012-2122 is a binary-level logic flaw in memcmp usage during authentication.
# The surgical mitigation is upgrading the package to a non-vulnerable version.
# Ubuntu 16.04 default repositories provide patched versions (5.7+).

# Identify installed database server packages silently
TARGET_PKGS=$(dpkg-query -W -f='${Package}\t${Status}\n' mysql-server mariadb-server 2>/dev/null | awk '/ok installed/ {print $1}' || true)

# If vulnerable software is detected, perform a surgical upgrade
if [ -n "$TARGET_PKGS" ]; then
    # Prevent interactive prompts during package upgrade
    export DEBIAN_FRONTEND=noninteractive

    # Update package definitions silently
    apt-get update -qq > /dev/null

    # Upgrade only the specific packages to the latest patched version available
    # --only-upgrade ensures we do not install the package if it's not already present
    apt-get install -yqq --only-upgrade $TARGET_PKGS > /dev/null
fi
```