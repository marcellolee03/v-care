```bash
#!/bin/bash
set -euo pipefail

# Configuration:
# The path where FCKeditor is detected. This is assumed to be an absolute
# filesystem path or a path directly targetable for mitigation.
# The vulnerability context provides "Location/URL: /cfide/scripts/ajax/FCKeditor".
# For a surgical script without web server configuration, we treat this as the
# direct filesystem path to the FCKeditor installation.
FCKEDITOR_INSTALL_PATH="/cfide/scripts/ajax/FCKeditor"
QUARANTINE_BASE_DIR="/var/quarantine"
QUARANTINE_EOL_DIR="${QUARANTINE_BASE_DIR}/eol_components"

# Function to log errors to stderr
log_error() {
    echo "ERROR: $1" >&2
}

# --- Main Script Logic ---

# 1. Verify script is run as root
if [[ "$(id -u)" -ne 0 ]]; then
    log_error "This script must be run as root to perform system modifications."
    exit 1
fi

# 2. Check if the FCKeditor installation path exists
# If it doesn't exist, the vulnerability is either already mitigated,
# or the component is not present at this specific path.
# The script is idempotent and silently exits in this case.
if [[ ! -e "${FCKEDITOR_INSTALL_PATH}" ]]; then
    exit 0
fi

# 3. Ensure the quarantine base directory exists and has restrictive permissions
if ! mkdir -p "${QUARANTINE_EOL_DIR}" 2>/dev/null; then
    log_error "Failed to create quarantine directory: '${QUARANTINE_EOL_DIR}'."
    exit 1
fi

# Set restrictive permissions (read/write/execute for owner only) on quarantine directory.
# This prevents unauthorized access to quarantined EOL software.
if ! chmod 0700 "${QUARANTINE_EOL_DIR}" 2>/dev/null; then
    log_error "Failed to set restrictive permissions on quarantine directory: '${QUARANTINE_EOL_DIR}'."
    exit 1
fi

# 4. Move the FCKeditor installation to the quarantine directory
# Append a timestamp to the item's name in quarantine to ensure uniqueness and prevent
# overwrites if multiple items with the same basename are quarantined over time.
ITEM_BASENAME=$(basename "${FCKEDITOR_INSTALL_PATH}")
QUARANTINED_NAME="${ITEM_BASENAME}_$(date +%Y%m%d%H%M%S)"

if ! mv "${FCKEDITOR_INSTALL_PATH}" "${QUARANTINE_EOL_DIR}/${QUARANTINED_NAME}" 2>/dev/null; then
    log_error "Failed to move FCKeditor from '${FCKEDITOR_INSTALL_PATH}' to quarantine."
    exit 1
fi

# Script exits silently on success, indicating the mitigation was applied or was not needed.
exit 0
```