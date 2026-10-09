```bash
#!/bin/bash
set -euo pipefail

# --- Configuration ---
TARGET_HADOOP_VERSION="2.8.4" # The fixed version for the 2.8.x branch of Apache Hadoop
# --- End Configuration ---

# --- Helper functions ---

# Function to compare versions (major.minor.patch)
# Returns 0 if $1 >= $2, 1 otherwise (i.e., $1 is greater than or equal to $2)
version_ge() {
    if [[ -z "$1" || -z "$2" ]]; then
        echo "Error: Two version strings must be provided for comparison in version_ge." >&2
        return 2
    fi
    local IFS='.'
    local v1_parts=($1)
    local v2_parts=($2)

    for i in 0 1 2; do # Assuming major.minor.patch format
        local p1=${v1_parts[$i]:-0} # Default to 0 if part is missing
        local p2=${v2_parts[$i]:-0}
        if (( 10#$p1 > 10#$p2 )); then
            return 0 # $1 is greater
        elif (( 10#$p1 < 10#$p2 )); then
            return 1 # $1 is smaller
        fi
    done
    return 0 # Versions are equal
}

# --- Main script ---

# 1. Verify root privileges
if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# 2. Get current Hadoop HDFS version and associated package name
CURRENT_HADOOP_VERSION=""
HADOOP_PACKAGE_NAME="" # To store the dynamically found package name if any

# Try to get version from 'hadoop version' command first
if command -v hadoop &> /dev/null; then
    HADOOP_VERSION_OUTPUT=$(hadoop version 2>&1)
    if echo "${HADOOP_VERSION_OUTPUT}" | grep -q "Hadoop"; then
        VERSION_CANDIDATE=$(echo "${HADOOP_VERSION_OUTPUT}" | grep "Hadoop" | head -n 1 | awk '{print $2}')
        # Validate and extract base version (e.g., 2.8.1 from 2.8.1-SNAPSHOT)
        if echo "${VERSION_CANDIDATE}" | grep -E -q '^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
            CURRENT_HADOOP_VERSION=$(echo "${VERSION_CANDIDATE}" | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*$/\1/')
        fi
    fi
fi

# Fallback: Try to get version from dpkg if 'hadoop version' failed or gave invalid output
if [[ -z "${CURRENT_HADOOP_VERSION}" ]]; then
    # Search for common Hadoop-related packages (e.g., hadoop-hdfs, hadoop-common)
    # and pick the first one to determine the version and package name.
    # This is an assumption based on typical Debian packaging.
    PACKAGE_LIST=$(dpkg -l | grep -i 'hadoop' | awk '{print $2}' | grep -E 'hdfs|common|core|mapreduce' || true) # '|| true' to prevent pipefail if grep finds nothing
    if [[ -n "${PACKAGE_LIST}" ]]; then
        HADOOP_PACKAGE_NAME=$(echo "${PACKAGE_LIST}" | head -n 1)

        if dpkg -s "${HADOOP_PACKAGE_NAME}" &> /dev/null; then
            VERSION_CANDIDATE=$(dpkg -s "${HADOOP_PACKAGE_NAME}" | grep '^Version:' | awk '{print $2}')
            # Extract base version (e.g., 2.8.1 from 2.8.1+dfsg-1)
            if echo "${VERSION_CANDIDATE}" | grep -E -q '^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?'; then
                CURRENT_HADOOP_VERSION=$(echo "${VERSION_CANDIDATE}" | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*$/\1/')
            fi
        fi
    fi
else # If version was found via 'hadoop version', try to find a package name for upgrade
    if [[ -z "${HADOOP_PACKAGE_NAME}" ]]; then
        PACKAGE_LIST=$(dpkg -l | grep -i 'hadoop' | awk '{print $2}' | grep -E 'hdfs|common|core|mapreduce' || true)
        if [[ -n "${PACKAGE_LIST}" ]]; then
            HADOOP_PACKAGE_NAME=$(echo "${PACKAGE_LIST}" | head -n 1)
        fi
    fi
fi

if [[ -z "${CURRENT_HADOOP_VERSION}" ]]; then
    echo "Error: Could not determine the current Apache Hadoop HDFS version. Cannot proceed with mitigation." >&2
    exit 1
fi

# 3. Check if mitigation is already applied (idempotency)
if version_ge "${CURRENT_HADOOP_VERSION}" "${TARGET_HADOOP_VERSION}"; then
    exit 0 # Silent success: Already fixed or newer version
fi

# If we reached here, the version is vulnerable.
# We must have HADOOP_PACKAGE_NAME to use apt-get.
if [[ -z "${HADOOP_PACKAGE_NAME}" ]]; then
    echo "Error: Apache Hadoop HDFS version ${CURRENT_HADOOP_VERSION} is vulnerable, but a Debian package name for Hadoop could not be determined. Unable to proceed with apt-get upgrade." >&2
    echo "Please identify the correct Hadoop package name (e.g., hadoop-hdfs, hadoop-common) or consider manual upgrade." >&2
    exit 1
fi

# 4. Attempt to upgrade Apache Hadoop HDFS
# Note: Debian 8 (Jessie) is End-Of-Life (EOL). Its default apt repositories
# might not provide the target fixed version (2.8.4). This script attempts
# the upgrade using standard apt tools, which is the "native command" approach.
# If the required version is not available, apt-get will report an error.

if ! apt-get update; then
    echo "Error: Failed to update package lists. Check network connectivity or apt sources." >&2
    exit 1
fi

# Attempt to install the specific fixed version.
# '--assume-yes' makes it non-interactive.
if ! apt-get install "${HADOOP_PACKAGE_NAME}=${TARGET_HADOOP_VERSION}" --assume-yes; then
    echo "Error: Failed to upgrade '${HADOOP_PACKAGE_NAME}' to version '${TARGET_HADOOP_VERSION}'." >&2
    echo "This is likely due to the target version not being available in the configured repositories for Debian 8 (Jessie), which is EOL." >&2
    echo "Manual intervention (e.g., adding backports, custom repositories, or manual compilation) may be required." >&2
    exit 1
fi

# 5. Verify the upgrade
# Re-check the version after the attempted upgrade
UPDATED_HADOOP_VERSION=""
if command -v hadoop &> /dev/null; then
    HADOOP_VERSION_OUTPUT=$(hadoop version 2>&1)
    if echo "${HADOOP_VERSION_OUTPUT}" | grep -q "Hadoop"; then
        VERSION_CANDIDATE=$(echo "${HADOOP_VERSION_OUTPUT}" | grep "Hadoop" | head -n 1 | awk '{print $2}')
        if echo "${VERSION_CANDIDATE}" | grep -E -q '^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
            UPDATED_HADOOP_VERSION=$(echo "${VERSION_CANDIDATE}" | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*$/\1/')
        fi
    fi
fi

if [[ -z "${UPDATED_HADOOP_VERSION}" && -n "${HADOOP_PACKAGE_NAME}" ]]; then
    if dpkg -s "${HADOOP_PACKAGE_NAME}" &> /dev/null; then
        VERSION_CANDIDATE=$(dpkg -s "${HADOOP_PACKAGE_NAME}" | grep '^Version:' | awk '{print $2}')
        if echo "${VERSION_CANDIDATE}" | grep -E -q '^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?'; then
            UPDATED_HADOOP_VERSION=$(echo "${VERSION_CANDIDATE}" | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*$/\1/')
        fi
    fi
fi

if version_ge "${UPDATED_HADOOP_VERSION}" "${TARGET_HADOOP_VERSION}"; then
    exit 0 # Silent success: Upgrade verified
else
    echo "Error: Failed to verify Apache Hadoop HDFS upgrade. Expected version >= ${TARGET_HADOOP_VERSION}, but found '${UPDATED_HADOOP_VERSION}'." >&2
    exit 1
fi
```