```bash
#!/bin/bash
# MITIGATION SCRIPT FOR CVE-2019-19846 (Joomla! SQLi Vulnerability)
# Role: Senior System Security Engineer and Linux Hardening Specialist
# Description: This script upgrades Joomla! to version 3.9.14 or newer to mitigate CVE-2019-19846.
# It is designed to be minimalist, surgical, and idempotent.

# --- Script Security & Error Handling ---
set -euo pipefail

# --- Pre-computation / Environment Check ---

# Verify root privileges
if [[ "${EUID}" -ne 0 ]]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# Determine potential Joomla! installation paths.
# The vulnerability context states "Installation path / port: /", which is ambiguous.
# Common web server document roots are checked.
JOOMLA_ROOT=""
POSSIBLE_DOC_ROOTS=("/var/www/html" "/var/www" "/srv/www" "/")

for doc_root in "${POSSIBLE_DOC_ROOTS[@]}"; do
    if [[ -f "${doc_root}/configuration.php" ]] && [[ -d "${doc_root}/libraries/cms" ]]; then
        JOOMLA_ROOT="${doc_root}"
        break
    fi
done

if [[ -z "${JOOMLA_ROOT}" ]]; then
    echo "Error: Joomla! installation not found in common web server document roots." >&2
    exit 1
fi

# Define the fixed version
FIXED_VERSION="3.9.14"
CURRENT_VERSION_FILE="${JOOMLA_ROOT}/libraries/cms/version/version.php"

# Check current Joomla! version
if [[ ! -f "${CURRENT_VERSION_FILE}" ]]; then
    echo "Error: Joomla! version file not found at ${CURRENT_VERSION_FILE}. Cannot determine current version." >&2
    exit 1
fi

# Extract current version using awk
CURRENT_VERSION=$(awk -F"'" '/JVERSION/{print $2}' "${CURRENT_VERSION_FILE}" 2>/dev/null)

if [[ -z "${CURRENT_VERSION}" ]]; then
    echo "Error: Could not determine current Joomla! version from ${CURRENT_VERSION_FILE}." >&2
    exit 1
fi

# Idempotence check: if current version is already at or above the fixed version, exit successfully.
if printf '%s\n' "${FIXED_VERSION}" "${CURRENT_VERSION}" | sort -V -C &>/dev/null; then
    # FIXED_VERSION is less than or equal to CURRENT_VERSION, meaning it's already fixed.
    echo "Joomla! is already at or above the fixed version (${FIXED_VERSION}). Current version: ${CURRENT_VERSION}. No action needed." >&2
    exit 0
fi

# --- Install necessary tools if missing ---
# 'unzip' is typically required for Joomla! full packages.
if ! command -v unzip &> /dev/null; then
    echo "Installing 'unzip' package (required for Joomla! update)..." >&2
    apt-get update >/dev/null || { echo "Error: Failed to update apt package lists." >&2; exit 1; }
    apt-get install -y unzip >/dev/null || { echo "Error: Failed to install 'unzip'." >&2; exit 1; }
fi

# --- Define Update Variables ---
JOOMLA_VERSION_TO_INSTALL="3.9.14" # Target version for the update
DOWNLOAD_URL="https://downloads.joomla.org/cms/joomla3/${JOOMLA_VERSION_TO_INSTALL}/Joomla_${JOOMLA_VERSION_TO_INSTALL}-Stable-Full_Package.zip"
TEMP_DIR=$(mktemp -d)
BACKUP_DIR=$(mktemp -d -t joomla_backup_XXXXXXXX)

# Ensure temporary directories are cleaned up on script exit
trap 'rm -rf "${TEMP_DIR}" "${BACKUP_DIR}"' EXIT

# --- Surgical Logic: Apply the Fix ---

echo "Starting Joomla! update from ${CURRENT_VERSION} to ${JOOMLA_VERSION_TO_INSTALL}..." >&2

# 1. Backup current Joomla! installation
echo "Backing up current Joomla! installation to ${BACKUP_DIR}..." >&2
cp -a "${JOOMLA_ROOT}/." "${BACKUP_DIR}/" || { echo "Error: Failed to backup Joomla! files." >&2; exit 1; }

# 2. Determine original ownership for restoration
OWNER=$(stat -c '%U' "${JOOMLA_ROOT}/configuration.php" 2>/dev/null) || OWNER="www-data" # Default to www-data if owner cannot be determined
GROUP=$(stat -c '%G' "${JOOMLA_ROOT}/configuration.php" 2>/dev/null) || GROUP="www-data" # Default to www-data if group cannot be determined

# 3. Download the new Joomla! full package
echo "Downloading Joomla! ${JOOMLA_VERSION_TO_INSTALL} from ${DOWNLOAD_URL}..." >&2
curl -sSL "${DOWNLOAD_URL}" -o "${TEMP_DIR}/joomla.zip" || { echo "Error: Failed to download Joomla! package." >&2; exit 1; }

# 4. Extract the new Joomla! package to a temporary location
echo "Extracting new Joomla! package to temporary directory..." >&2
unzip -q "${TEMP_DIR}/joomla.zip" -d "${TEMP_DIR}/joomla_new/" || { echo "Error: Failed to extract Joomla! package." >&2; exit 1; }

# 5. Apply the file update: This involves moving the configuration.php, clearing the old installation,
#    copying the new files, and restoring configuration.php.

echo "Applying Joomla! file update..." >&2

# Temporarily move configuration.php to prevent it from being overwritten
mv "${JOOMLA_ROOT}/configuration.php" "${TEMP_DIR}/configuration.php.orig" || { echo "Error: Failed to move configuration.php for update." >&2; exit 1; }

# Remove all existing files and directories from the Joomla! root (except the root itself)
# This ensures old, potentially vulnerable files are completely removed.
find "${JOOMLA_ROOT}" -mindepth 1 -delete || { echo "Error: Failed to clear old Joomla! files from ${JOOMLA_ROOT}." >&2; exit 1; }

# Copy the new Joomla! files into the now empty Joomla! root
cp -a "${TEMP_DIR}/joomla_new/." "${JOOMLA_ROOT}/" || { echo "Error: Failed to copy new Joomla! files to ${JOOMLA_ROOT}." >&2; exit 1; }

# Restore the original configuration.php
mv "${TEMP_DIR}/configuration.php.orig" "${JOOMLA_ROOT}/configuration.php" || { echo "Error: Failed to restore configuration.php after update." >&2; exit 1; }

# 6. Restore file permissions and ownership
echo "Restoring file permissions and ownership (Owner: ${OWNER}, Group: ${GROUP})..." >&2
chown -R "${OWNER}:${GROUP}" "${JOOMLA_ROOT}" || { echo "Error: Failed to restore ownership for ${JOOMLA_ROOT}." >&2; exit 1; }

# Set common Joomla! directory and file permissions
find "${JOOMLA_ROOT}" -type d -exec chmod 0755 {} + || { echo "Error: Failed to set directory permissions." >&2; exit 1; }
find "${JOOMLA_ROOT}" -type f -exec chmod 0644 {} + || { echo "Error: Failed to set file permissions." >&2; exit 1; }

# Set stricter permissions for specific critical files/directories
chmod 0640 "${JOOMLA_ROOT}/configuration.php" 2>/dev/null || true
chmod 0755 "${JOOMLA_ROOT}/cache" "${JOOMLA_ROOT}/logs" "${JOOMLA_ROOT}/tmp" 2>/dev/null || true

# --- Verification ---
echo "Verifying updated Joomla! version..." >&2
UPDATED_VERSION=$(awk -F"'" '/JVERSION/{print $2}' "${CURRENT_VERSION_FILE}" 2>/dev/null)

if printf '%s\n' "${FIXED_VERSION}" "${UPDATED_VERSION}" | sort -V -C &>/dev/null; then
    echo "Joomla! successfully updated to version ${UPDATED_VERSION}." >&2
    echo "Note: Joomla! database schema updates may still be required via the administrator interface." >&2
else
    echo "Error: Joomla! update verification failed. Expected version >= ${FIXED_VERSION}, but found ${UPDATED_VERSION}." >&2
    echo "Please check the installation and perform manual database migration via the Joomla! administrator interface if necessary." >&2
    exit 1
fi

# Script exits successfully (trap handles cleanup).
```