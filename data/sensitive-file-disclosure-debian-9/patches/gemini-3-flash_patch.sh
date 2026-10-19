```bash
#!/bin/bash
set -euo pipefail

# Role: Senior System Security Engineer
# Mitigation for CVE-2017-16894: Sensitive File Disclosure (HTTP)
# Target: Microsoft IIS web.config files in vendor directories on Linux

# Verify root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Root privileges required." >&2
    exit 1
fi

# Locate and remove web.config files within vendor directories.
# These files are Microsoft IIS artifacts often bundled with PHP/Composer packages.
# On a Debian/Linux system, they provide no functionality but leak application 
# structure and configuration metadata to remote attackers.
# Logic is idempotent: find -delete executes only if files exist and returns success otherwise.

TARGET_ROOTS=("/var/www" "/opt" "/usr/share" "/var/lib")

for root in "${TARGET_ROOTS[@]}"; do
    if [ -d "$root" ]; then
        find "$root" -type f -name "web.config" -path "*/vendor/*" -delete 2>/dev/null || true
    fi
done
```