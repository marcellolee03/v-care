```bash
#!/bin/bash
set -euo pipefail

# Define vulnerability and fix details
ETCD_FIX_VERSION="3.4.26"
ETCD_DOWNLOAD_URL_BASE="https://github.com/etcd-io/etcd/releases/download/v${ETCD_FIX_VERSION}/etcd-v${ETCD_FIX_VERSION}-linux-amd64.tar.gz"
DOWNLOAD_DIR="/tmp/etcd_update_$$"

# Function to report errors to stderr and exit
err() {
    echo "Error: $*" >&2
    exit 1
}

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root."
fi

# --- Idempotence Check & Current Version Detection ---

# Attempt to find the etcd binary in PATH
ETCD_BINARY_PATH=$(which etcd 2>/dev/null)
if [[ -z "${ETCD_BINARY_PATH}" ]]; then
    err "etcd binary not found in PATH. Cannot determine current version or apply fix."
fi

# Get current etcd version
CURRENT_ETCD_VERSION=$(etcd --version 2>&1 | awk '/etcd Version:/ {print $3}')

if [[ -z "${CURRENT_ETCD_VERSION}" ]]; then
    err "Could not determine current etcd version from '${ETCD_BINARY_PATH} --version'."
fi

# Perform version comparison: if CURRENT_ETCD_VERSION is less than ETCD_FIX_VERSION, it's vulnerable.
# Uses 'sort -V' for robust semantic version comparison.
if [[ "$(printf '%s\n' "${CURRENT_ETCD_VERSION}" "${ETCD_FIX_VERSION}" | sort -V | head -1)" == "${CURRENT_ETCD_VERSION}" && "${CURRENT_ETCD_VERSION}" != "${ETCD_FIX_VERSION}" ]]; then
    # Vulnerable, proceed with mitigation
    :
else
    # Not vulnerable or already fixed, exit silently
    exit 0
fi

# --- Mitigation Steps ---

ETCD_SERVICE_NAME="etcd"
ETCD_RUNNING_BINARY_PATH="${ETCD_BINARY_PATH}" # Default to 'which etcd' result
ETCDCTL_RUNNING_BINARY_PATH="$(dirname "${ETCD_RUNNING_BINARY_PATH}")/etcdctl"
SERVICE_WAS_ACTIVE=false

# Check if etcd service exists and is active
if systemctl is-active --quiet "${ETCD_SERVICE_NAME}"; then
    SERVICE_WAS_ACTIVE=true
    # Try to get the actual binary path from the systemd unit file
    SERVICE_BINARY_PATH=$(systemctl show "${ETCD_SERVICE_NAME}" -p ExecStart 2>/dev/null | sed 's/^ExecStart=//' | awk '{print $1}')
    if [[ -n "${SERVICE_BINARY_PATH}" && -x "${SERVICE_BINARY_PATH}" ]]; then
        ETCD_RUNNING_BINARY_PATH="${SERVICE_BINARY_PATH}"
        ETCDCTL_RUNNING_BINARY_PATH="$(dirname "${SERVICE_BINARY_PATH}")/etcdctl"
    fi
    systemctl stop "${ETCD_SERVICE_NAME}" || err "Failed to stop etcd service."
    sleep 5 # Give service time to gracefully stop
fi

# Create a temporary directory for download and extraction
mkdir -p "${DOWNLOAD_DIR}" || err "Failed to create temporary directory ${DOWNLOAD_DIR}."
cd "${DOWNLOAD_DIR}" || err "Failed to change to temporary directory ${DOWNLOAD_DIR}."

# Download and extract the new etcd binaries
curl -sSL "${ETCD_DOWNLOAD_URL_BASE}" -o etcd.tar.gz || err "Failed to download etcd archive from ${ETCD_DOWNLOAD_URL_BASE}."
tar -xzf etcd.tar.gz || err "Failed to extract etcd archive."

# Locate the extracted directory and verify binaries
EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name "etcd-v${ETCD_FIX_VERSION}*" -print -quit)
if [[ -z "${EXTRACTED_DIR}" || ! -d "${EXTRACTED_DIR}" ]]; then
    err "Extracted etcd directory not found in ${DOWNLOAD_DIR}."
fi
if [[ ! -x "${EXTRACTED_DIR}/etcd" ]]; then
    err "New etcd binary not found or not executable in ${EXTRACTED_DIR}."
fi
if [[ ! -x "${EXTRACTED_DIR}/etcdctl" ]]; then
    err "New etcdctl binary not found or not executable in ${EXTRACTED_DIR}."
fi

# Backup existing binaries before replacement
if [[ -f "${ETCD_RUNNING_BINARY_PATH}" ]]; then
    mv "${ETCD_RUNNING_BINARY_PATH}" "${ETCD_RUNNING_BINARY_PATH}.bak" || err "Failed to backup old etcd binary."
fi
if [[ -f "${ETCDCTL_RUNNING_BINARY_PATH}" ]]; then
    mv "${ETCDCTL_RUNNING_BINARY_PATH}" "${ETCDCTL_RUNNING_BINARY_PATH}.bak" || err "Failed to backup old etcdctl binary."
fi

# Place new binaries
cp "${EXTRACTED_DIR}/etcd" "${ETCD_RUNNING_BINARY_PATH}" || err "Failed to place new etcd binary."
cp "${EXTRACTED_DIR}/etcdctl" "${ETCDCTL_RUNNING_BINARY_PATH}" || err "Failed to place new etcdctl binary."

# Set appropriate permissions and ownership for the new binaries
chmod 755 "${ETCD_RUNNING_BINARY_PATH}" || err "Failed to set executable permissions on new etcd binary."
chown root:root "${ETCD_RUNNING_BINARY_PATH}" || err "Failed to set ownership on new etcd binary."

chmod 755 "${ETCDCTL_RUNNING_BINARY_PATH}" || err "Failed to set executable permissions on new etcdctl binary."
chown root:root "${ETCDCTL_RUNNING_BINARY_PATH}" || err "Failed to set ownership on new etcdctl binary."

# Clean up temporary directory
cd / || err "Failed to change directory to /."
rm -rf "${DOWNLOAD_DIR}" || err "Failed to clean up temporary directory ${DOWNLOAD_DIR}."

# Restart etcd service if it was active previously
if "${SERVICE_WAS_ACTIVE}"; then
    systemctl start "${ETCD_SERVICE_NAME}" || err "Failed to start etcd service after update."
    systemctl is-active --quiet "${ETCD_SERVICE_NAME}" || err "etcd service failed to become active after update."
fi

# --- Post-Mitigation Verification ---
NEW_ETCD_VERSION=$(etcd --version 2>&1 | awk '/etcd Version:/ {print $3}')
if [[ "${NEW_ETCD_VERSION}" == "${ETCD_FIX_VERSION}" ]]; then
    exit 0 # Success, exit silently
else
    err "Failed to verify etcd update. Current version: ${NEW_ETCD_VERSION}, Expected: ${ETCD_FIX_VERSION}."
fi
```