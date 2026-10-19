```bash
#!/bin/bash
set -euo pipefail

# --- Configuration ---
# The target jQuery file path as identified in the vulnerability report.
# Assumed to be an absolute path on the filesystem.
TARGET_FILE="/themes/default/js/jquery.js"
# URL to download the fixed version of jQuery (1.9.0 minified).
FIXED_VERSION_URL="https://code.jquery.com/jquery-1.9.0.min.js"
# The minimum required jQuery version to mitigate the vulnerability.
REQUIRED_VERSION="1.9.0"

# --- Functions ---

# Prints an error message to stderr and exits with status 1.
error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

# Checks if the script is run with root privileges.
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        error_exit "This script must be run as root."
    fi
}

# Extracts the jQuery version from a given file.
# Looks for patterns like "jQuery v1.2.3" or "jQuery v1.2".
# Arguments:
#   $1 - Path to the jQuery file.
# Returns:
#   The version string (e.g., "1.7.1") or an empty string if not found.
get_version() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo ""
        return
    fi
    # Use awk to find the version string. The pattern `jQuery v[0-9]+\.[0-9]+(\.[0-9]+)?`
    # matches versions with two or three components (e.g., v1.7, v1.7.1).
    # `-F'[ v]'` sets ' ' or 'v' as field separators. The version number is typically the 3rd field.
    # `exit` ensures it only prints the first match and stops.
    awk -F'[ v]' '/jQuery v[0-9]+\.[0-9]+(\.[0-9]+)?/{print $3; exit}' "$file"
}

# Compares two version strings (e.g., "1.9.0" and "1.7.1").
# Returns 0 if the first version is greater than or equal to the second, 1 otherwise.
# Arguments:
#   $1 - The first version string.
#   $2 - The second version string (the baseline).
version_gt_or_eq() {
    # Sorts the baseline ($2) then the target ($1) version using version sort (-V).
    # If the output is already sorted (i.e., $2 comes before or is equal to $1),
    # `sort -C` returns 0, indicating $1 >= $2. Otherwise, it returns 1.
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

# --- Main Script ---

check_root

# Validate the target file exists.
if [[ ! -f "$TARGET_FILE" ]]; then
    error_exit "Target jQuery file not found at: $TARGET_FILE. Please ensure the path is correct."
fi

# Get the currently installed jQuery version.
CURRENT_VERSION=$(get_version "$TARGET_FILE")

# If the version cannot be determined, it's an unexpected state.
if [[ -z "$CURRENT_VERSION" ]]; then
    error_exit "Could not determine jQuery version from $TARGET_FILE. Aborting mitigation."
fi

# Check for idempotence: If the version is already fixed or newer, exit silently.
if version_gt_or_eq "$CURRENT_VERSION" "$REQUIRED_VERSION"; then
    exit 0 # Already fixed, silent success
fi

# At this point, the installed version is vulnerable. Proceed with mitigation.

# Create a timestamped backup of the original vulnerable file.
BACKUP_FILE="${TARGET_FILE}.bak.$(date +%Y%m%d%H%M%S)"
cp "$TARGET_FILE" "$BACKUP_FILE" || error_exit "Failed to create backup of '$TARGET_FILE' to '$BACKUP_FILE'."

# Download the fixed version of jQuery to a temporary file.
TEMP_JQUERY_FILE=$(mktemp)
# `curl -sS` ensures silent output unless an error occurs (`-s`) and shows progress (`-S`).
curl -sS -o "$TEMP_JQUERY_FILE" "$FIXED_VERSION_URL" || error_exit "Failed to download jQuery $REQUIRED_VERSION from $FIXED_VERSION_URL."

# Replace the vulnerable file with the newly downloaded fixed version.
# `mv` preserves permissions and ownership if target is on the same filesystem.
mv "$TEMP_JQUERY_FILE" "$TARGET_FILE" || error_exit "Failed to replace '$TARGET_FILE' with the new version."

# Verify that the new version is correctly installed.
NEW_INSTALLED_VERSION=$(get_version "$TARGET_FILE")
if ! version_gt_or_eq "$NEW_INSTALLED_VERSION" "$REQUIRED_VERSION"; then
    error_exit "Verification failed: New jQuery version ('$NEW_INSTALLED_VERSION') is not '$REQUIRED_VERSION' or newer after update."
fi

# Script completes successfully and silently.
```