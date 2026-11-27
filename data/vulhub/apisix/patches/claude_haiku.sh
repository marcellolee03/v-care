#!/usr/bin/env bash
# Remediation: etcd 3.4.15 -> 3.4.26 (GHSA-3p4g-rcw5-8298 / CVE-2023-32082)
# Strategy: patch_update from the upstream release tarball, installed over the
# existing binary in place. Data directory and command line are unchanged, so the
# original entrypoint keeps working after `docker restart`.

set -euo pipefail

TARGET_VERSION="3.4.26"
FIXED_MIN="3.4.26"
BACKUP_DIR="/usr/local/share/etcd-backup-pre-${TARGET_VERSION}"
WORK_DIR="$(mktemp -d /tmp/etcd-remediate.XXXXXX)"

log()  { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
die()  { log "ERROR: $*"; rm -rf "$WORK_DIR"; exit 1; }
trap 'rm -rf "$WORK_DIR"' EXIT

# Version comparison helper: returns 0 if $1 >= $2 (dotted numeric)
version_ge() {
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

# 1. Locate the installed etcd binary (PID 1 may be etcd itself)
ETCD_BIN=""
if [ -e /proc/1/exe ]; then
    pid1_exe="$(readlink -f /proc/1/exe 2>/dev/null || true)"
    case "$(basename "${pid1_exe:-}")" in
        etcd) ETCD_BIN="$pid1_exe" ;;
    esac
fi
if [ -z "$ETCD_BIN" ]; then
    ETCD_BIN="$(command -v etcd 2>/dev/null || true)"
fi
if [ -z "$ETCD_BIN" ]; then
    for c in /usr/local/bin/etcd /usr/bin/etcd /usr/local/etcd/etcd; do
        if [ -x "$c" ]; then ETCD_BIN="$c"; break; fi
    done
fi
[ -n "$ETCD_BIN" ] && [ -x "$ETCD_BIN" ] || die "etcd binary not found"
ETCD_BIN="$(readlink -f "$ETCD_BIN")"
ETCD_DIR="$(dirname "$ETCD_BIN")"
log "Found etcd binary: $ETCD_BIN"

# 2. Check current version; skip if already fixed
current_raw="$("$ETCD_BIN" --version 2>/dev/null | awk '/etcd Version/{print $3; exit}')"
current_ver="${current_raw:-unknown}"
log "Current etcd version: $current_ver"
if [ "$current_ver" != "unknown" ] && version_ge "$current_ver" "$FIXED_MIN"; then
    log "Already at or above $FIXED_MIN; nothing to do."
    exit 0
fi

# 3. Determine architecture
case "$(uname -m)" in
    x86_64|amd64)  ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) die "unsupported architecture: $(uname -m)" ;;
esac

# 4. Ensure a download tool exists (curl is not in the tool list; install it if possible)
DL=""
if command -v curl >/dev/null 2>&1; then
    DL="curl"
elif command -v wget >/dev/null 2>&1; then
    DL="wget"
else
    export DEBIAN_FRONTEND=noninteractive
    log "No curl/wget found; attempting to install curl via apt"
    apt-get update -y >/dev/null 2>&1 || log "WARN: apt-get update failed (continuing)"
    apt-get install -y --no-install-recommends curl ca-certificates >/dev/null 2>&1 \
        || die "unable to install curl (no usable package repository)"
    DL="curl"
fi

fetch() {
    local url="$1" out="$2"
    if [ "$DL" = "curl" ]; then
        curl -fsSL --retry 3 --connect-timeout 20 -o "$out" "$url"
    else
        wget -q -T 20 -t 3 -O "$out" "$url"
    fi
}

# 5. Download the fixed release tarball
TARBALL="etcd-v${TARGET_VERSION}-linux-${ARCH}.tar.gz"
URL="https://github.com/etcd-io/etcd/releases/download/v${TARGET_VERSION}/${TARBALL}"
log "Downloading $URL"
fetch "$URL" "$WORK_DIR/$TARBALL" || die "download failed; original binary left untouched"

# 6. Extract and validate
tar -xzf "$WORK_DIR/$TARBALL" -C "$WORK_DIR" || die "tarball extraction failed"
EXTRACT_DIR="$WORK_DIR/etcd-v${TARGET_VERSION}-linux-${ARCH}"
[ -x "$EXTRACT_DIR/etcd" ] || die "etcd binary missing from tarball"

new_ver="$("$EXTRACT_DIR/etcd" --version 2>/dev/null | awk '/etcd Version/{print $3; exit}')"
[ "$new_ver" = "$TARGET_VERSION" ] || die "downloaded binary reports version '${new_ver:-none}', expected $TARGET_VERSION"
log "Verified new etcd binary version: $new_ver"

# 7. Back up existing binaries (persisted under /usr/local)
mkdir -p "$BACKUP_DIR"
cp -p "$ETCD_BIN" "$BACKUP_DIR/etcd" 2>/dev/null || die "backup of etcd failed"
if [ -x "$ETCD_DIR/etcdctl" ]; then
    cp -p "$ETCD_DIR/etcdctl" "$BACKUP_DIR/etcdctl" 2>/dev/null || true
fi
log "Backed up original binaries to $BACKUP_DIR"

# 8. Install new binaries. Use write-to-temp then rename so that a running
#    executable is never written in place ("Text file busy" safe).
install_bin() {
    local src="$1" dst="$2"
    cp -f "$src" "$dst.new"
    chmod 0755 "$dst.new"
    mv -f "$dst.new" "$dst"
}
install_bin "$EXTRACT_DIR/etcd" "$ETCD_BIN"
if [ -f "$ETCD_DIR/etcdctl" ] || [ -x "$EXTRACT_DIR/etcdctl" ]; then
    install_bin "$EXTRACT_DIR/etcdctl" "$ETCD_DIR/etcdctl"
fi

# 9. Post-install verification
final_ver="$("$ETCD_BIN" --version 2>/dev/null | awk '/etcd Version/{print $3; exit}')"
if [ "$final_ver" != "$TARGET_VERSION" ]; then
    log "Post-install version check failed; restoring backup"
    cp -f "$BACKUP_DIR/etcd" "$ETCD_BIN" || true
    die "installed version '${final_ver:-none}' != $TARGET_VERSION"
fi

log "etcd upgraded from $current_ver to $final_ver."
log "Restart the container so the running process picks up the new binary."
exit 0