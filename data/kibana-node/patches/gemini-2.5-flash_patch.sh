```bash
#!/bin/bash
# Minimalist, surgical, and idempotent BASH script to mitigate Kibana Node.js security vulnerabilities.

# Security: Exit immediately if a command exits with a non-zero status.
# Exit if any unset variables are encountered.
# The return value of a pipeline is the status of the last command to exit with a non-zero status, or zero if all commands in the pipeline exit successfully.
set -euo pipefail

# --- Configuration Variables ---
KIBANA_PACKAGE="kibana"
REQUIRED_KIBANA_VERSION="7.14.1" # The fixed version or newer

# --- Functions ---

# Function to report errors to stderr and exit
error_report() {
    echo "ERROR: $1" >&2
    exit 1
}

# Function to compare two semantic versions (e.g., "1.2.3" vs "1.2.4")
# Arguments: v1, v2
# Returns:
#   0 if v1 == v2
#   1 if v1 > v2
#   2 if v1 < v2
version_compare() {
    if [[ -z "$1" || -z "$2" ]]; then
        error_report "version_compare: Missing version argument. Usage: version_compare v1 v2"
    fi

    local v1="$1"
    local v2="$2"
    IFS='.' read -r -a a <<< "$v1"
    IFS='.' read -r -a b <<< "$v2"

    local i
    for ((i = 0; i < ${#a[@]} || i < ${#b[@]}; i++)); do
        local part_a=${a[i]:-0} # Default to 0 if part is missing
        local part_b=${b[i]:-0}

        if (( part_a > part_b )); then
            return 1 # v1 > v2
        elif (( part_a < part_b )); then
            return 2 # v1 < v2
        fi
    done
    return 0 # v1 == v2
}

# --- Main Script Logic ---

# 1. Root privilege check
if [[ "$EUID" -ne 0 ]]; then
    error_report "This script must be run as root."
fi

# 2. Idempotence check: Determine current Kibana version and compare with required version.
installed_version=$(rpm -q --qf '%{VERSION}' "$KIBANA_PACKAGE" 2>/dev/null || true)

if [[ -z "$installed_version" ]]; then
    error_report "Kibana package '$KIBANA_PACKAGE' not found. Please ensure Kibana is installed via YUM."
fi

version_compare "$installed_version" "$REQUIRED_KIBANA_VERSION"
compare_result=$?

if [[ "$compare_result" -eq 0 || "$compare_result" -eq 1 ]]; then
    # Current installed version is equal to or greater than the required fixed version.
    # The vulnerability is already mitigated. Exit silently.
    exit 0
fi

# If we reach here, it means installed_version < REQUIRED_KIBANA_VERSION, so an upgrade is needed.

# 3. Stop Kibana service gracefully before upgrade.
# Check if the service is active before attempting to stop to avoid unnecessary errors.
if systemctl is-active --quiet "$KIBANA_PACKAGE"; then
    systemctl stop "$KIBANA_PACKAGE" || error_report "Failed to stop Kibana service."
fi

# 4. Perform the Kibana package upgrade.
# Use '-y' for non-interactive upgrade. Redirect stdout to /dev/null for silent success.
yum update -y "$KIBANA_PACKAGE" >/dev/null || error_report "Failed to upgrade Kibana. Check YUM repositories and network connectivity."

# 5. Start Kibana service after upgrade.
systemctl start "$KIBANA_PACKAGE" || error_report "Failed to start Kibana service after upgrade."

# Script executed successfully (upgrade performed).
exit 0
```