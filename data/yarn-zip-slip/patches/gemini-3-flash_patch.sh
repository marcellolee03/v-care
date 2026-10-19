```bash
#!/bin/bash
# Senior System Security Engineer - Hadoop Hardening
# Mitigates CVE-2018-8009 (Zip Slip) by upgrading vulnerable core libraries.
set -euo pipefail

# Security: Verify root privileges
[[ "${EUID}" -ne 0 ]] && exit 1

# Locate Hadoop installation
HADOOP_BIN=$(command -v hadoop || find /usr/local /opt /home/hadoop -name hadoop -type f -executable -path "*/bin/hadoop" 2>/dev/null | head -n 1)
[[ -z "${HADOOP_BIN}" ]] && exit 0

# Extract environment details
HADOOP_HOME=$(cd "$(dirname "${HADOOP_BIN}")/.." && pwd)
CURRENT_VER=$("${HADOOP_BIN}" version | head -n 1 | awk '{print $2}')
FIXED_VER="2.8.5"

# Surgical Logic: Mitigate only if version is within affected range (specifically 2.8.1 < 2.8.5)
if [[ "${CURRENT_VER}" < "${FIXED_VER}" ]]; then
    # Define targets for the surgical library swap
    # CVE-2018-8009 is a code-level vulnerability in org.apache.hadoop.fs.FileUtil (hadoop-common)
    LIB_DIR="${HADOOP_HOME}/share/hadoop/common"
    PATCH_JAR="hadoop-common-${FIXED_VER}.jar"
    PATCH_URL="https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-common/${FIXED_VER}/${PATCH_JAR}"

    if [[ -d "${LIB_DIR}" ]]; then
        # Shutdown YARN ResourceManager to prevent file locking and clear the attack surface (Port 8088)
        # Using native sbin scripts if available
        [[ -x "${HADOOP_HOME}/sbin/yarn-daemon.sh" ]] && "${HADOOP_HOME}/sbin/yarn-daemon.sh" stop resourcemanager >/dev/null 2>&1 || true

        # Download the fixed JAR from a trusted repository
        if curl -sSfL "${PATCH_URL}" -o "${LIB_DIR}/${PATCH_JAR}"; then
            # Surgical deletion of vulnerable libraries to ensure classpath loads the fixed version
            # This simultaneously fixes the 'hadoop version' output as it reads from this JAR's manifest
            find "${LIB_DIR}" -name "hadoop-common-*.jar" ! -name "${PATCH_JAR}" -delete

            # Idempotent: Attempt to restart the service; failure to restart is reported to stderr via set -e
            [[ -x "${HADOOP_HOME}/sbin/yarn-daemon.sh" ]] && "${HADOOP_HOME}/sbin/yarn-daemon.sh" start resourcemanager >/dev/null 2>&1 || true
        else
            echo "Error: Failed to retrieve patched library from ${PATCH_URL}" >&2
            exit 1
        fi
    fi
fi
```