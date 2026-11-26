#!/bin/bash
set -Eeuo pipefail

ADMINER_VERSION="4.16.0"
WEBROOT="/var/www/html"
TMPDIR="$(mktemp -d /tmp/adminer-remediation.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

log() { printf '[adminer-fix] %s\n' "$*" >&2; }

# Make HTTPS downloads work if the image has no CA bundle.
if [ ! -s /etc/ssl/certs/ca-certificates.crt ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1 || true
    apt-get install -y -qq --no-install-recommends ca-certificates >/dev/null 2>&1 || true
fi

download() {
    local url="$1" out="$2"
    rm -f "$out"
    if curl -fsSL --connect-timeout 15 --max-time 180 "$url" -o "$out" 2>/dev/null; then
        return 0
    fi
    if curl -fsSLk --connect-timeout 15 --max-time 180 "$url" -o "$out" 2>/dev/null; then
        return 0
    fi
    rm -f "$out"
    return 1
}

valid_adminer() {
    local file="$1" v
    [ -s "$file" ] || return 1
    grep -q '<?php' "$file" 2>/dev/null || return 1
    grep -q 'adminer\.org' "$file" 2>/dev/null || return 1
    grep -q 'Adminer' "$file" 2>/dev/null || return 1
    php -l "$file" >/dev/null 2>&1 || return 1

    v="$(grep -m1 -oE '@version[[:space:]]+[0-9]+(\.[0-9]+)+' "$file" 2>/dev/null | awk '{print $2}' || true)"
    if [ -z "${v:-}" ]; then
        v="$(grep -m1 -oE 'Adminer[[:space:]]+[0-9]+(\.[0-9]+)+' "$file" 2>/dev/null | awk '{print $2}' || true)"
    fi
    if [ -z "${v:-}" ]; then
        grep -q "$ADMINER_VERSION" "$file" 2>/dev/null || return 1
        return 0
    fi
    php -r 'exit(version_compare($argv[1], $argv[2], ">=") ? 0 : 1);' "$v" "$ADMINER_VERSION" >/dev/null 2>&1
}

FIXED="$TMPDIR/adminer-$ADMINER_VERSION.php"
URLS=(
    "https://www.adminer.org/static/download/${ADMINER_VERSION}/adminer-${ADMINER_VERSION}.php"
    "https://www.adminer.org/static/download/${ADMINER_VERSION}/adminer-${ADMINER_VERSION}-en.php"
    "https://github.com/vrana/adminer/releases/download/v${ADMINER_VERSION}/adminer-${ADMINER_VERSION}.php"
    "https://github.com/vrana/adminer/releases/download/v${ADMINER_VERSION}/adminer-${ADMINER_VERSION}-en.php"
    "https://github.com/vrana/adminer/releases/download/v${ADMINER_VERSION}/adminer.php"
    "https://raw.githubusercontent.com/vrana/adminer/v${ADMINER_VERSION}/adminer.php"
    "https://www.adminer.org/latest.php"
)

downloaded=0
for url in "${URLS[@]}"; do
    log "Trying $url"
    if download "$url" "$FIXED" && valid_adminer "$FIXED"; then
        downloaded=1
        break
    fi
done

if [ "$downloaded" -ne 1 ]; then
    log "Unable to obtain a valid Adminer $ADMINER_VERSION package"
    exit 1
fi
log "Downloaded and validated Adminer $ADMINER_VERSION"

TARGETS=()

add_target() {
    local f="$1" t
    [ -f "$f" ] || return 0
    if [ ${#TARGETS[@]} -gt 0 ]; then
        for t in "${TARGETS[@]}"; do
            [ "$t" = "$f" ] && return 0
        done
    fi
    TARGETS+=("$f")
}

scan_root() {
    local root="$1" f
    [ -d "$root" ] || return 0
    while IFS= read -r f; do
        if grep -q 'adminer\.org' "$f" 2>/dev/null && grep -qE '@version[[:space:]]+[0-9]' "$f" 2>/dev/null; then
            add_target "$f"
        fi
    done < <(find -L "$root" -maxdepth 5 -type f -name '*.php' 2>/dev/null || true)
}

scan_root "$WEBROOT"
scan_root "/usr/share/adminer"

if [ ${#TARGETS[@]} -eq 0 ]; then
    for c in "$WEBROOT/index.php" "$WEBROOT/adminer.php"; do
        if [ -f "$c" ] && grep -qi 'adminer' "$c" 2>/dev/null; then
            add_target "$c"
        fi
    done
fi

if [ ${#TARGETS[@]} -eq 0 ]; then
    while IFS= read -r f; do
        if grep -q '4\.7\.8' "$f" 2>/dev/null; then
            add_target "$f"
        fi
    done < <(find -L "$WEBROOT" -maxdepth 5 -type f -name '*.php' 2>/dev/null || true)
fi

if [ ${#TARGETS[@]} -eq 0 ]; then
    mkdir -p "$WEBROOT"
    TARGETS+=("$WEBROOT/index.php")
    log "No existing Adminer entry point detected; installing at $WEBROOT/index.php"
fi

i=0
for f in "${TARGETS[@]}"; do
    b="$TMPDIR/orig-$i.php"
    i=$((i + 1))

    if [ -f "$f" ]; then
        cp -p "$f" "$b" 2>/dev/null || true
    fi

    chattr -i "$f" 2>/dev/null || true
    cat "$FIXED" > "$f"

    if [ -f "$b" ]; then
        chmod --reference="$b" "$f" 2>/dev/null || chmod 0644 "$f"
        chown --reference="$b" "$f" 2>/dev/null || true
    else
        chmod 0644 "$f" 2>/dev/null || true
    fi

    if ! valid_adminer "$f"; then
        log "Fixed-file verification failed for $f"
        exit 1
    fi
    log "Installed Adminer $ADMINER_VERSION at $f"
done

if command -v curl >/dev/null 2>&1; then
    if curl -fsS --max-time 15 http://127.0.0.1/ -o "$TMPDIR/served.html" 2>/dev/null; then
        if grep -q "$ADMINER_VERSION" "$TMPDIR/served.html"; then
            log "HTTP check confirms Adminer $ADMINER_VERSION is being served"
        else
            log "HTTP check did not yet show $ADMINER_VERSION; it will take effect after the container restart"
        fi
    fi
fi

exit 0