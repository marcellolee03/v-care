```bash
#!/bin/bash
set -euo pipefail

# --- Configuration ---
TARGET_JOOMLA_VERSION="3.6.5"
JOOMLA_DOWNLOAD_URL="https://downloads.joomla.org/cms/joomla3/3-6-5/Joomla_3.6.5-Stable-Full_Package.zip"
DOWNLOAD_FILENAME="Joomla_3.6.5-Stable-Full_Package.zip"
WEB_USER="www-data" # Common web server user for Apache/Nginx on Debian. Adjust if different.

# --- Functions ---

# Function to display error messages to stderr and exit
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# Function to compare versions (major.minor.patch)
# Returns 0 if $1 is greater than or equal to $2, 1 otherwise.
version_ge() {
    printf '%s\n%s\n' "$1" "$2" | sort -CV >/dev/null
}

# --- Main Script ---

# 1. Check for root privileges
if [[ "${EUID}" -ne 0 ]]; then
    error_exit "This script must be run as root."
fi

# 2. Find Joomla installation path
JOOMLA_ROOT=""
# List of common paths where Joomla might be installed.
# The script will search for 'configuration.php' and 'libraries/cms/version/version.php'
# to identify the Joomla root directory.
CANDIDATE_PATHS=(
    "/var/www/html"
    "/srv/www/joomla"
    "/var/www/joomla"
    "/usr/share/joomla"
)

for path in "${CANDIDATE_PATHS[@]}"; do
    if [ -f "${path}/configuration.php" ] && [ -f "${path}/libraries/cms/version/version.php" ]; then
        JOOMLA_ROOT="${path}"
        break
    fi
done

if [ -z "${JOOMLA_ROOT}" ]; then
    error_exit "Joomla installation not found in common web roots (${CANDIDATE_PATHS[*]}). Please ensure it's installed or adjust the CANDIDATE_PATHS variable."
fi

# 3. Check current Joomla version
JOOMLA_VERSION_FILE="${JOOMLA_ROOT}/libraries/cms/version/version.php"
if [ ! -f "${JOOMLA_VERSION_FILE}" ]; then
    error_exit "Joomla version file not found at ${JOOMLA_VERSION_FILE}. Cannot determine current version."
fi

# Extract MAJOR, MINOR, PATCH components from the version file
JOOMLA_MAJOR=$(grep -E "^\s*public\s+\$MAJOR\s*=" "${JOOMLA_VERSION_FILE}" | head -1 | sed -E 's/.*=\s*([0-9]+);/\1/')
JOOMLA_MINOR=$(grep -E "^\s*public\s+\$MINOR\s*=" "${JOOMLA_VERSION_FILE}" | head -1 | sed -E 's/.*=\s*([0-9]+);/\1/')
JOOMLA_PATCH=$(grep -E "^\s*public\s+\$PATCH\s*=" "${JOOMLA_VERSION_FILE}" | head -1 | sed -E 's/.*=\s*([0-9]+);/\1/')

# Construct the current version string for comparison (e.g., "3.4.2")
CURRENT_JOOMLA_VERSION="${JOOMLA_MAJOR}.${JOOMLA_MINOR}.${JOOMLA_PATCH}"

# Compare current version with the target fixed version
if version_ge "${CURRENT_JOOMLA_VERSION}" "${TARGET_JOOMLA_VERSION}"; then
    # Joomla is already at or above the target version. Script is idempotent.
    exit 0
fi

# 4. Install 'unzip' if not present (strictly necessary for package extraction)
if ! command -v unzip >/dev/null; then
    echo "Info: 'unzip' not found. Installing it now." >&2 # Inform user via stderr
    apt-get update >/dev/null || error_exit "Failed to run apt-get update."
    apt-get install -y unzip >/dev/null || error_exit "Failed to install 'unzip' package."
fi

# 5. Create a temporary directory for download and extraction
TMP_DIR=$(mktemp -d)
if [ ! -d "${TMP_DIR}" ]; then
    error_exit "Failed to create temporary directory."
fi
# Ensure cleanup of the temporary directory on script exit
trap 'rm -rf "${TMP_DIR}"' EXIT

# 6. Backup existing Joomla installation
BACKUP_DIR="${JOOMLA_ROOT}_bak_$(date +%Y%m%d%H%M%S)"
mv "${JOOMLA_ROOT}" "${BACKUP_DIR}" || error_exit "Failed to backup Joomla installation to ${BACKUP_DIR}."

# 7. Download the Joomla 3.6.5 full package
curl -sSL "${JOOMLA_DOWNLOAD_URL}" -o "${TMP_DIR}/${DOWNLOAD_FILENAME}" || error_exit "Failed to download Joomla package from ${JOOMLA_DOWNLOAD_URL}."

# 8. Extract the package to the original Joomla root
mkdir -p "${JOOMLA_ROOT}" || error_exit "Failed to recreate Joomla installation directory at ${JOOMLA_ROOT}."
unzip -q "${TMP_DIR}/${DOWNLOAD_FILENAME}" -d "${JOOMLA_ROOT}" || error_exit "Failed to extract Joomla package to ${JOOMLA_ROOT}."

# 9. Restore the critical 'configuration.php' file from the backup
# The full package often overwrites this, which is undesirable as it contains site-specific settings.
if [ -f "${BACKUP_DIR}/configuration.php" ]; then
    cp "${BACKUP_DIR}/configuration.php" "${JOOMLA_ROOT}/configuration.php" || error_exit "Failed to restore configuration.php."
fi

# 10. Set appropriate file permissions and ownership
# This ensures the web server can read/write necessary files.
if ! chown -R "${WEB_USER}:${WEB_USER}" "${JOOMLA_ROOT}"; then
    echo "Warning: Failed to set ownership to ${WEB_USER}. Please ensure this user exists and has correct permissions setup for Joomla, or adjust WEB_USER." >&2
fi
find "${JOOMLA_ROOT}" -type d -exec chmod 0755 {} \;
find "${JOOMLA_ROOT}" -type f -exec chmod 0644 {} \;
# Set stricter permissions for configuration.php if possible
chmod 0640 "${JOOMLA_ROOT}/configuration.php" 2>/dev/null || true
```