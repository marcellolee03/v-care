```bash
#!/bin/bash

# Ensure script stops on errors, undefined variables, and pipe failures
set -euo pipefail

# Verify root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# Locate the vulnerable jQuery file based on the NVT detection path
# We search in common web directories first to be surgical and efficient
TARGET_FILE=$(find /var/www /usr/share /opt /home -type f -path "*/themes/default/js/jquery.js" 2>/dev/null | head -n 1)

# If not found in common paths, perform a broader search
if [ -z "$TARGET_FILE" ]; then
    TARGET_FILE=$(find / -type f -path "*/themes/default/js/jquery.js" 2>/dev/null | head -n 1)
fi

# Exit silently if the file does not exist (idempotency/nothing to patch)
[ -z "$TARGET_FILE" ] && exit 0

# Idempotency check: Identify if version is < 1.9.0
# Vulnerable versions 1.0.x through 1.8.x are targeted for upgrade
if grep -qE "jQuery v1\.[0-8]\." "$TARGET_FILE"; then
    # jQuery 1.12.4 is the last of the 1.x branch, providing maximum 
    # compatibility while resolving CVE-2012-6708 and subsequent 1.x XSS issues.
    FIX_URL="https://code.jquery.com/jquery-1.12.4.min.js"
    TMP_PATCH=$(mktemp)

    # Download fixed version using curl (using -k for legacy CA compatibility in Debian 8)
    if curl -skSf "$FIX_URL" -o "$TMP_PATCH"; then
        # Use cat to overwrite contents to preserve existing file attributes/permissions
        cat "$TMP_PATCH" > "$TARGET_FILE"
        rm -f "$TMP_PATCH"
    else
        rm -f "$TMP_PATCH"
        echo "Error: Failed to download secure jQuery version from $FIX_URL" >&2
        exit 1
    fi
fi
```