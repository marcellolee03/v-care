#!/bin/sh
set -eu

VERSION="3.4.26"
WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/etcd-fix.XXXXXX")
cleanup() {
    rm -rf "$WORKDIR"
}
trap cleanup EXIT HUP INT TERM

log() {
    printf '%s\n' "$*" >&2
}

case "$(uname -m)" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    ppc64le) ARCH="ppc64le" ;;
    s390x) ARCH="s390x" ;;
    i386|i486|i586|i686) ARCH="386" ;;
    *)
        log "Unsupported architecture: $(uname -m)"
        exit 1
        ;;
esac

ARCHIVE="etcd-v${VERSION}-linux-${ARCH}.tar.gz"
PRIMARY_URL="https://github.com/etcd-io/etcd/releases/download/v${VERSION}/${ARCHIVE}"

apt_try_install() {
    [ "$#" -gt 0 ] || return 1
    command -v apt-get >/dev/null 2>&1 || return 1

    DEBIAN_FRONTEND=noninteractive apt-get update \
        -o Acquire::Check-Valid-Until=false >/dev/null 2>&1 || true

    if DEBIAN_FRONTEND=noninteractive apt-get install \
        -y --no-install-recommends "$@" >/dev/null 2>&1; then
        return 0
    fi

    APT_LIST="$WORKDIR/archive.list"
    {
        echo "deb [trusted=yes] http://archive.debian.org/debian stretch main"
        echo "deb [trusted=yes] http://archive.debian.org/debian-security stretch/updates main"
    } > "$APT_LIST"

    DEBIAN_FRONTEND=noninteractive apt-get \
        -o Dir::Etc::sourcelist="$APT_LIST" \
        -o Dir::Etc::sourceparts="-" \
        -o Acquire::Check-Valid-Until=false \
        -o Acquire::Check-Date=false \
        -o APT::Get::List-Cleanup="0" \
        update >/dev/null 2>&1 || true

    DEBIAN_FRONTEND=noninteractive apt-get \
        -o Dir::Etc::sourcelist="$APT_LIST" \
        -o Dir::Etc::sourceparts="-" \
        -o Acquire::Check-Valid-Until=false \
        -o Acquire::Check-Date=false \
        -y --no-install-recommends install "$@" >/dev/null 2>&1
}

download_file() {
    url=$1
    out=$2

    if command -v curl >/dev/null 2>&1; then
        if curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 \
            --max-time 300 --proto '=https' --tlsv1.2 \
            -o "$out" "$url" >/dev/null 2>&1; then
            return 0
        fi
    fi

    if command -v wget >/dev/null 2>&1; then
        if wget -q --timeout=30 --tries=3 -O "$out" "$url" >/dev/null 2>&1; then
            return 0
        fi
    fi

    return 1
}

download_asset() {
    for url in \
        "$PRIMARY_URL" \
        "https://storage.googleapis.com/etcd/v${VERSION}/${ARCHIVE}" \
        "https://storage.googleapis.com/etcd/${ARCHIVE}"
    do
        rm -f "$WORKDIR/$ARCHIVE"
        if download_file "$url" "$WORKDIR/$ARCHIVE"; then
            if [ -s "$WORKDIR/$ARCHIVE" ]; then
                return 0
            fi
        fi
    done
    return 1
}

if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    log "No HTTP downloader found; attempting to install curl"
    apt_try_install curl ca-certificates || true
fi

if ! download_asset; then
    log "Initial download failed; attempting to install CA certificates and retry"
    apt_try_install ca-certificates || true
    if ! download_asset; then
        log "Unable to download etcd ${VERSION} archive"
        exit 1
    fi
fi

if ! tar -tzf "$WORKDIR/$ARCHIVE" >/dev/null 2>&1; then
    log "Downloaded etcd archive is not a valid gzip tarball"
    exit 1
fi

tar -xzf "$WORKDIR/$ARCHIVE" -C "$WORKDIR"

EXTRACTED="$WORKDIR/etcd-v${VERSION}-linux-${ARCH}"
NEW_ETCD="$EXTRACTED/etcd"
NEW_ETCDCTL="$EXTRACTED/etcdctl"

if [ ! -x "$NEW_ETCD" ]; then
    NEW_ETCD=$(find "$WORKDIR" -type f -name etcd -perm -u+x 2>/dev/null | head -n 1 || true)
fi
if [ ! -x "$NEW_ETCDCTL" ]; then
    NEW_ETCDCTL=$(find "$WORKDIR" -type f -name etcdctl -perm -u+x 2>/dev/null | head -n 1 || true)
fi

if [ -z "$NEW_ETCD" ] || [ ! -x "$NEW_ETCD" ]; then
    log "etcd binary not found in downloaded archive"
    exit 1
fi

chmod 0755 "$NEW_ETCD"
[ -n "$NEW_ETCDCTL" ] && chmod 0755 "$NEW_ETCDCTL"

if ! "$NEW_ETCD" --version > "$WORKDIR/version-check.txt" 2>&1; then
    log "Downloaded etcd binary could not be executed"
    cat "$WORKDIR/version-check.txt" >&2 || true
    exit 1
fi
if ! grep -F "etcd Version: ${VERSION}" "$WORKDIR/version-check.txt" >/dev/null 2>&1; then
    log "Downloaded etcd binary is not version ${VERSION}"
    cat "$WORKDIR/version-check.txt" >&2 || true
    exit 1
fi

find_etcd_target() {
    if [ -e /proc/1/exe ]; then
        p=$(readlink -f /proc/1/exe 2>/dev/null || true)
        case "$p" in
            */etcd|*/etcd-*)
                if [ -f "$p" ]; then
                    printf '%s\n' "$p"
                    return 0
                fi
                ;;
        esac
    fi

    if [ -r /proc/1/cmdline ]; then
        arg0=$(tr '\0' '\n' < /proc/1/cmdline | head -n 1)
        case "$arg0" in
            /*/etcd|/*/etcd-*)
                if [ -f "$arg0" ]; then
                    printf '%s\n' "$arg0"
                    return 0
                fi
                ;;
        esac
    fi

    for p in /usr/local/bin/etcd /usr/local/etcd/etcd /usr/bin/etcd /bin/etcd /opt/etcd/etcd; do
        if [ -f "$p" ]; then
            p=$(readlink -f "$p" 2>/dev/null || printf '%s\n' "$p")
            printf '%s\n' "$p"
            return 0
        fi
    done

    if command -v etcd >/dev/null 2>&1; then
        p=$(command -v etcd)
        p=$(readlink -f "$p" 2>/dev/null || printf '%s\n' "$p")
        if [ -f "$p" ]; then
            printf '%s\n' "$p"
            return 0
        fi
    fi

    p=$(find /usr/local /opt /usr/bin -maxdepth 5 -type f -name etcd 2>/dev/null | head -n 1 || true)
    if [ -n "$p" ]; then
        printf '%s\n' "$p"
        return 0
    fi

    return 1
}

install_binary() {
    src=$1
    dst=$2
    dst=$(readlink -f "$dst" 2>/dev/null || printf '%s\n' "$dst")
    [ -n "$dst" ] || return 1

    dst_dir=$(dirname "$dst")
    mkdir -p "$dst_dir"

    tmp_dst="$dst_dir/.etcd-install.$$"
    cp "$src" "$tmp_dst"
    chmod 0755 "$tmp_dst"
    chown 0:0 "$tmp_dst" 2>/dev/null || true

    if [ -f "$dst" ] && [ ! -e "$dst.pre-$VERSION" ]; then
        cp -p "$dst" "$dst.pre-$VERSION" 2>/dev/null || true
    fi

    mv -f "$tmp_dst" "$dst"
}

TARGET_ETCD=$(find_etcd_target) || {
    log "Could not locate the installed etcd binary"
    exit 1
}

install_binary "$NEW_ETCD" "$TARGET_ETCD"

if [ -n "$NEW_ETCDCTL" ] && [ -x "$NEW_ETCDCTL" ]; then
    TARGET_ETCDCTL=""
    if command -v etcdctl >/dev/null 2>&1; then
        TARGET_ETCDCTL=$(command -v etcdctl)
    elif [ -f /usr/local/bin/etcdctl ]; then
        TARGET_ETCDCTL="/usr/local/bin/etcdctl"
    fi
    if [ -n "$TARGET_ETCDCTL" ]; then
        install_binary "$NEW_ETCDCTL" "$TARGET_ETCDCTL" || true
    fi
fi

if ! "$TARGET_ETCD" --version > "$WORKDIR/final-version.txt" 2>&1; then
    log "Installed etcd binary failed its version check"
    cat "$WORKDIR/final-version.txt" >&2 || true
    exit 1
fi
if ! grep -F "etcd Version: ${VERSION}" "$WORKDIR/final-version.txt" >/dev/null 2>&1; then
    log "Installed etcd binary does not report version ${VERSION}"
    cat "$WORKDIR/final-version.txt" >&2 || true
    exit 1
fi

log "etcd ${VERSION} installed at ${TARGET_ETCD}; restart the container to activate it."
exit 0