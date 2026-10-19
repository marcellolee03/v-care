```bash
#!/bin/bash

# Apply strict error handling
set -euo pipefail

# Verify root privileges
if [ "$EUID" -ne 0 ]; then
    echo "This script requires root privileges" >&2
    exit 1
fi

# Variables
HADOOP_VERSION="2.8.1"
FIXED_VERSIONS=("2.8.4" "2.9.1" "3.0.1")
HADOOP_CONFIG_DIR="/etc/hadoop"
HADOOP_HDFS_CONFIG="${HADOOP_CONFIG_DIR}/hdfs-site.xml"

# Function to check if version is vulnerable
is_vulnerable_version() {
    local current="$1"
    
    # Check major.minor version patterns
    case "$current" in
        3.0.0-alpha*|3.0.0)
            return 0
            ;;
        2.9.0)
            return 0
            ;;
        2.[5-7].*)
            # Check if version is between 2.5.0 and 2.7.5
            local version_num
            version_num=$(echo "$current" | awk -F. '{printf "%d%03d%03d", $1, $2, $3}')
            if [ "$version_num" -ge 2005000 ] && [ "$version_num" -le 2007005 ]; then
                return 0
            fi
            ;;
        2.8.*)
            # Check if version is between 2.8.0 and 2.8.3
            local patch
            patch=$(echo "$current" | awk -F. '{print $3}')
            if [ "${patch:-0}" -le 3 ]; then
                return 0
            fi
            ;;
    esac
    return 1
}

# Function to apply security restriction
apply_xattr_fix() {
    if [ ! -f "$HADOOP_HDFS_CONFIG" ]; then
        echo "HDFS configuration not found: ${HADOOP_HDFS_CONFIG}" >&2
        exit 1
    fi
    
    # Create backup before modification
    cp "${HADOOP_HDFS_CONFIG}" "${HADOOP_HDFS_CONFIG}.backup-$(date +%Y%m%d%H%M%S)"
    
    # Add or update the xattr configuration property
    if grep -q "<name>dfs.namenode.xattrs.enabled</name>" "$HADOOP_HDFS_CONFIG"; then
        # Update existing property
        sed -i '/<name>dfs.namenode.xattrs.enabled<\/name>/,/<\/value>/s/<value>.*<\/value>/<value>false<\/value>/' "$HADOOP_HDFS_CONFIG"
    else
        # Add new property inside configuration section
        if grep -q "</configuration>" "$HADOOP_HDFS_CONFIG"; then
            sed -i '/<\/configuration>/i\
    <property>\
        <name>dfs.namenode.xattrs.enabled</name>\
        <value>false</value>\
    </property>' "$HADOOP_HDFS_CONFIG"
        else
            # Configuration tag not found, append at end
            echo '    <property>
        <name>dfs.namenode.xattrs.enabled</name>
        <value>false</value>
    </property>
</configuration>' >> "$HADOOP_HDFS_CONFIG"
        fi
    fi
}

# Function to restart Hadoop services
restart_hadoop_services() {
    # Attempt to restart HDFS services
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart hadoop-hdfs-namenode 2>/dev/null || true
        systemctl restart hadoop-hdfs-secondarynamenode 2>/dev/null || true
    elif command -v service >/dev/null 2>&1; then
        service hadoop-hdfs-namenode restart 2>/dev/null || true
        service hadoop-hdfs-secondarynamenode restart 2>/dev/null || true
    fi
}

# Main execution
if is_vulnerable_version "$HADOOP_VERSION"; then
    apply_xattr_fix
    restart_hadoop_services
fi
```