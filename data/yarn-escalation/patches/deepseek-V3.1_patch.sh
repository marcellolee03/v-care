```bash
#!/bin/bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

HADOOP_DIR="/"
VULNERABLE_VERSION="2.8.1"
FIXED_VERSION="2.8.5"

# Check if Hadoop is installed and get version
if [[ ! -d "$HADOOP_DIR" ]]; then
    echo "Error: Hadoop installation directory not found" >&2
    exit 1
fi

# Verify vulnerable version presence (simplified check)
if [[ -f "${HADOOP_DIR}/bin/hadoop" ]]; then
    CURRENT_VERSION=$("${HADOOP_DIR}/bin/hadoop" version 2>/dev/null | awk '/Hadoop/{print $2}' || true)
    if [[ "$CURRENT_VERSION" == "$VULNERABLE_VERSION" ]]; then
        # Mitigation: Remove world-writable permissions from sensitive directories
        find "${HADOOP_DIR}" -type d -perm -o+w -name "tmp" -o -name "temp" -exec chmod o-w {} \; 2>/dev/null || true
        
        # Secure configuration: Disable vulnerable features if present
        if [[ -f "${HADOOP_DIR}/etc/hadoop/core-site.xml" ]]; then
            sed -i 's/<value>.*0\.0\.0\.0.*<\/value>/<value>localhost<\/value>/g' "${HADOOP_DIR}/etc/hadoop/core-site.xml" 2>/dev/null || true
        fi
    fi
fi

exit 0
```