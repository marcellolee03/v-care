```bash
#!/bin/bash
# Script to mitigate jQuery XSS Vulnerability (CVE-2012-6708)
# by upgrading jQuery 1.7.2 to 1.9.0 in place.

set -euo pipefail

# --- Configuration Variables ---
TARGET_FILENAME="jquery-1.7.2.min.js"
FIXED_VERSION_URL="https://code.jquery.com/jquery-1.9.0.min.js"
# Heuristic search paths for common Airflow installations.
# The vulnerability context specifies an 'airflow' user and a Debian 10 OS,
# suggesting a typical Airflow web UI setup. The file is expected to be
# within a path resembling ".../airflow/www/static/js/".
# These paths are ordered to search more standard system locations first.
SEARCH_PATHS="/usr/local /opt /var/www /home/airflow"

# --- Functions ---

# error_exit: Prints an error message to stderr and exits with status 1.
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# --- Main Script Logic ---

# 1. Verify script is run as root for necessary file system operations.
if [[ "$(id -u)" -ne 0 ]]; then
    error_exit "This script must be run as root."
fi

# 2. Create a temporary directory for downloaded files.
TEMP_DIR=$(mktemp -d)
# Flag to control cleanup on script exit. Initially true.
# Set to false if no changes were made to avoid trying to cleanup non-existent files.
CLEANUP_REQUIRED=true

# Setup cleanup trap: ensures the temporary directory is removed on script exit (success or failure).
cleanup() {
    if "$CLEANUP_REQUIRED"; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

# 3. Locate the vulnerable file on the filesystem.
# This step searches for the specific jQuery file within common Airflow static asset patterns.
VULNERABLE_FILE=""
for search_path in $SEARCH_PATHS; do
    # Use -path to match the full path, -type f for regular files, -print -quit to stop after first match.
    # Redirect stderr to /dev/null to suppress 'Permission denied' errors from find in unreadable directories.
    VULNERABLE_FILE=$(find "$search_path" -type f -path "*/airflow/www/static/js/$TARGET_FILENAME" -print -quit 2>/dev/null)
    if [[ -n "$VULNERABLE_FILE" ]]; then
        break
    fi
done

if [[ -z "$VULNERABLE_FILE" ]]; then
    error_exit "Vulnerable file '$TARGET_FILENAME' not found under common Airflow installation paths ('$SEARCH_PATHS'). Manual intervention or path adjustment may be required."
fi

# 4. Idempotence Check: Determine if the file is already patched or a newer version.
# We check for 'jQuery v1.9' or any version starting with 'v2' or 'v3' etc. in the file content.
# 'grep -q' runs silently and returns 0 if found, 1 if not found.
# Redirect stderr to /dev/null to suppress potential grep errors on malformed files.
if grep -qE 'jQuery v(1\.9|[2-9]\.)' "$VULNERABLE_FILE" 2>/dev/null; then
    # File already contains jQuery 1.9.0 or a newer version string.
    CLEANUP_REQUIRED=false # No system changes were made, so no temp files to clean up from this script.
    exit 0 # Exit silently as no action is needed (idempotence).
fi

# 5. Download the fixed jQuery version.
DOWNLOADED_FILE="$TEMP_DIR/jquery-1.9.0.min.js"
# curl options: -f (fail silently on HTTP errors), -s (silent), -S (show error if -s is used), -L (follow redirects)
if ! curl -fsSL "$FIXED_VERSION_URL" -o "$DOWNLOADED_FILE"; then
    error_exit "Failed to download fixed jQuery version from $FIXED_VERSION_URL. Check network connectivity or URL."
fi

# Verify the downloaded file is not empty.
if [[ ! -s "$DOWNLOADED_FILE" ]]; then
    error_exit "Downloaded jQuery file is empty or missing at '$DOWNLOADED_FILE'."
fi

# 6. Backup the original vulnerable file.
# Backup filename includes a timestamp to ensure uniqueness.
BACKUP_FILE="${VULNERABLE_FILE}.$(date +%Y%m%d%H%M%S).bak"
if ! cp "$VULNERABLE_FILE" "$BACKUP_FILE"; then
    error_exit "Failed to create backup of '$VULNERABLE_FILE' to '$BACKUP_FILE'."
fi

# 7. Replace the vulnerable file with the fixed version.
# This operation effectively updates the content of the existing file.
if ! cp "$DOWNLOADED_FILE" "$VULNERABLE_FILE"; then
    error_exit "Failed to replace '$VULNERABLE_FILE' with the fixed version."
fi

# 8. Restore original permissions and ownership from the backup.
# This ensures the web server or application can still read/access the file correctly.
# Default to 644 for permissions and root:root for owner:group if stat fails (e.g., if backup failed).
ORIGINAL_PERMS=$(stat -c %a "$BACKUP_FILE" 2>/dev/null || echo "644")
ORIGINAL_OWNER_GROUP=$(stat -c %U:%G "$BACKUP_FILE" 2>/dev/null || echo "root:root")

# Attempt to restore permissions.
if ! chmod "$ORIGINAL_PERMS" "$VULNERABLE_FILE"; then
    echo "Warning: Failed to set original permissions '$ORIGINAL_PERMS' on '$VULNERABLE_FILE'." >&2
fi

# Attempt to restore ownership.
if ! chown "$ORIGINAL_OWNER_GROUP" "$VULNERABLE_FILE"; then
    echo "Warning: Failed to set original owner:group '$ORIGINAL_OWNER_GROUP' on '$VULNERABLE_FILE'." >&2
fi

# Mitigation complete. The web server or application might need a restart
# for changes to take effect if it heavily caches static files.
# However, this script is focused on the file system fix as per "minimalist" and "surgical" requirements,
# without making assumptions about specific service names or restart mechanisms.

# Final cleanup of the temporary directory is handled by the trap EXIT.
exit 0 # Script finished successfully and silently.
```