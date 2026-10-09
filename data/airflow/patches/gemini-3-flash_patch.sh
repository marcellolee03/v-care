```bash
#!/bin/bash
set -euo pipefail

# Mitigation Script for CVE-2012-6708 (jQuery < 1.9.0 XSS)
# Role: Senior System Security Engineer
# Environment: Debian 10 (Buster), Airflow context

# 1. Verify root privileges
if [ "$(id -u)" -ne 0 ]; then
    exit 1
fi

# 2. Define target parameters
# The vulnerability is identified in jquery-1.7.2.min.js
# The fix is to upgrade to at least version 1.9.0
TARGET_NAME="jquery-1.7.2.min.js"
FIXED_SOURCE="https://code.jquery.com/jquery-1.9.0.min.js"
SEARCH_ROOTS=("/usr/local/lib" "/var/www" "/usr/share" "/home/airflow")

# 3. Locate vulnerable instances and apply surgical fix
# Use a while loop to handle potential spaces in file paths safely
find "${SEARCH_ROOTS[@]}" -type f -name "$TARGET_NAME" 2>/dev/null | while read -r target_path; do
    
    # Idempotency: Check if the file content already contains the fixed version string
    # This prevents redundant downloads and ensures the script can be run multiple times
    if grep -q "v1.9.0" "$target_path"; then
        continue
    fi

    # Create a temporary file for the secure version
    tmp_file=$(mktemp)
    
    # Fetch the fixed version from a trusted source
    if curl -sL "$FIXED_SOURCE" -o "$tmp_file" && [ -s "$tmp_file" ]; then
        # Perform surgical replacement
        # Using cat into the file preserves the original file's ownership and permissions
        cat "$tmp_file" > "$target_path"
        rm -f "$tmp_file"
    else
        # Report failure to stderr
        echo "Error: Failed to patch $target_path - version fetch failed" >&2
        rm -f "$tmp_file"
        exit 1
    fi
done
```