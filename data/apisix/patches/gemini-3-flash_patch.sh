```bash
#!/bin/bash
set -euo pipefail

[[ "${EUID}" -ne 0 ]] && { echo "Error: root privileges required" >&2; exit 1; }

ETCD_BIN=$(command -v etcd 2>/dev/null) || exit 0
CURRENT_VER=$("${ETCD_BIN}" --version | awk '/etcd Version:/ {print $3}')
FIXED_VER="3.4.26"

# Check if current version is lower than the fixed version
if [[ "$(printf '%s\n%s' "${FIXED_VER}" "${CURRENT_VER}" | sort -V | head -n1)" == "${FIXED_VER}" ]]; then
    exit 0
fi

ARCH=$(uname -m)
case "${ARCH}" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) echo "Error: Architecture ${ARCH} not supported" >&2; exit 1 ;;
esac

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "${TEMP_DIR}"' EXIT

URL="https://github.com/etcd-io/etcd/releases/download/v${FIXED_VER}/etcd-v${FIXED_VER}-linux-${ARCH}.tar.gz"

if ! curl -sSL "${URL}" -o "${TEMP_DIR}/etcd.tar.gz"; then
    echo "Error: Failed to download etcd v${FIXED_VER}" >&2
    exit 1
fi

tar -xzf "${TEMP_DIR}/etcd.tar.gz" -C "${TEMP_DIR}" --strip-components=1 >/dev/null 2>&1

# Surgical binary replacement
cp "${ETCD_BIN}" "${ETCD_BIN}.bak"
install -m 0755 "${TEMP_DIR}/etcd" "${ETCD_BIN}"

# Update etcdctl if present
ETCDCTL_BIN=$(command -v etcdctl 2>/dev/null || echo "$(dirname "${ETCD_BIN}")/etcdctl")
[[ -f "${TEMP_DIR}/etcdctl" ]] && install -m 0755 "${TEMP_DIR}/etcdctl" "${ETCDCTL_BIN}"

# Idempotent service restart
if systemctl is-active --quiet etcd; then
    systemctl restart etcd || { echo "Error: Failed to restart etcd" >&2; exit 1; }
fi
```