```bash
#!/bin/bash
# Minimalist mitigation script for CVE-2018-8029 (Apache Hadoop Privilege Escalation)
# Target: Hadoop >= 2.2.0 and < 2.8.5
# Strategy: Surgical upgrade to 2.8.5 binaries for the common library.

set -euo pipefail

# Security: Ensure root privileges
if [[ "$(id -u)" -ne 0 ]]; then
    exit 1
fi

# Detect Hadoop executable
HADOOP_BIN=$(command -v hadoop 2>/dev/null) || exit 0
HADOOP_HOME=$(dirname "$(dirname "$(readlink -f "$HADOOP_BIN")")")

# Extract current version
CURRENT_VERSION=$("$HADOOP_BIN" version | head -n 1 | awk '{print $2}')

# Idempotency: Check if version is already >= 2.8.5
# Using sort -V for version comparison logic
FIXED_VERSION="2.8.5"
IS_VULNERABLE=$(printf '%s\n%s' "$FIXED_VERSION" "$CURRENT_VERSION" | sort -V | head -n 1)

if [[ "$IS_VULNERABLE" == "$FIXED_VERSION" && "$CURRENT_VERSION" != "$FIXED_VERSION" ]]; then
    # Already fixed or higher version
    exit 0
fi

# Surgical Upgrade Logic
# CVE-2018-8029 resides in the hadoop-common component (UGI class)
TMP_DIR=$(mktemp -d)
DL_URL="https://archive.apache.org/dist/hadoop/common/hadoop-${FIXED_VERSION}/hadoop-${FIXED_VERSION}.tar.gz"

# Download and extract only the necessary binaries and libraries to HADOOP_HOME
# This maintains existing configuration in etc/hadoop/
curl -sSL "$DL_URL" | tar -xz -C "$TMP_DIR" --strip-components=1

# Perform surgical replacement of bin, lib, and share directories
# Excludes 'etc' to preserve cluster configuration
for DIR in bin sbin lib share; do
    if [[ -d "${HADOOP_HOME}/${DIR}" ]]; then
        # Synchronize new binaries while removing old versions of jars
        # Use simple cp/rm logic to remain POSIX/minimalist
        rm -rf "${HADOOP_HOME:?}/${DIR}"
        cp -rp "${TMP_DIR}/${DIR}" "${HADOOP_HOME}/"
    fi
done

# Cleanup
rm -rf "$TMP_DIR"

# Verify fix
NEW_VERSION=$("$HADOOP_BIN" version | head -n 1 | awk '{print $2}')
if [[ "$NEW_VERSION" != "$FIXED_VERSION" ]]; then
    echo "Mitigation failed: Version mismatch." >&2
    exit 1
fi
```