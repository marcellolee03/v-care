```bash
#!/bin/bash
# Mitigates Elasticsearch End of Life (EOL) vulnerability.
# This script stops, disables, and purges the Elasticsearch service and package
# to ensure the EOL software is no longer present or active on the system.

# --- Security and Error Handling ---
set -euo pipefail
IFS=$'\n\t'

# Verify that the script is run with root privileges.
if [[ "${EUID}" -ne 0 ]]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# --- Constants ---
ELASTICSEARCH_SERVICE_NAME="elasticsearch.service"
ELASTICSEARCH_PACKAGE_NAME="elasticsearch" # Common Debian package name for Elasticsearch

# --- Mitigation Logic ---

# 1. Stop and disable the Elasticsearch service.
# Check if the service unit exists and is recognized by systemd.
if systemctl status "${ELASTICSEARCH_SERVICE_NAME}" &> /dev/null; then
    # Stop the service if it's currently active.
    if systemctl is-active --quiet "${ELASTICSEARCH_SERVICE_NAME}"; then
        echo "Stopping ${ELASTICSEARCH_SERVICE_NAME}..." >&2
        if ! systemctl stop "${ELASTICSEARCH_SERVICE_NAME}"; then
            echo "Error: Failed to stop ${ELASTICSEARCH_SERVICE_NAME}." >&2
            exit 1
        fi
    fi

    # Disable the service to prevent it from starting automatically on boot.
    if systemctl is-enabled --quiet "${ELASTICSEARCH_SERVICE_NAME}"; then
        echo "Disabling ${ELASTICSEARCH_SERVICE_NAME}..." >&2
        if ! systemctl disable "${ELASTICSEARCH_SERVICE_NAME}"; then
            echo "Error: Failed to disable ${ELASTICSEARCH_SERVICE_NAME}." >&2
            exit 1
        fi
    fi
fi

# 2. Purge the Elasticsearch package.
# This step removes the software binaries and configuration files,
# fully mitigating the presence of the EOL version.
if dpkg -s "${ELASTICSEARCH_PACKAGE_NAME}" &> /dev/null; then
    echo "Purging ${ELASTICSEARCH_PACKAGE_NAME} package..." >&2

    # Update package lists to ensure apt-get has current information.
    # This is not strictly the mitigation, but a prerequisite for robust purging.
    if ! apt-get update; then
        echo "Warning: Failed to update apt package lists. Proceeding with purge anyway." >&2
    fi

    # Use 'purge' to remove configuration files and '--autoremove' to clean up dependencies.
    if ! apt-get purge --autoremove -y "${ELASTICSEARCH_PACKAGE_NAME}"; then
        echo "Error: Failed to purge ${ELASTICSEARCH_PACKAGE_NAME} package." >&2
        exit 1
    fi
fi

# 3. Final verification for any residual Elasticsearch processes.
# This check acts as a warning if Elasticsearch was installed or is running
# in a non-standard way not managed by systemd or apt.
if pgrep -f "elasticsearch" > /dev/null; then
    echo "Warning: Elasticsearch processes still detected after mitigation attempts. Manual intervention may be required to remove non-standard installations." >&2
    exit 1 # Indicate that full mitigation might not have been achieved.
fi

exit 0
```