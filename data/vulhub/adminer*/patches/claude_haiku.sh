#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

INSTALL_ROOT="/var/www/html"
FIXED_VERSION="4.16.0"
NEW_VERSION="4.16.1"
DOWNLOAD_URL="https://github.com/vrana/adminer/releases/download/v${NEW_VERSION}/adminer-${NEW_VERSION}.php"
BACKUP_DIR="/root/adminer-backup-$(date -u +%Y%m%d%H%M%S)"
TMP_FILE="$(mktemp /tmp/adminer-new.XXXXXX.php)"

cleanup() { rm -f "$TMP_FILE"; }
trap cleanup EXIT

log()  { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
die()  { log "ERROR: $*"; exit 1; }

# Returns 0 if version $1 is lower than $2 (both X.Y.Z)
version_lt() {
    [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ]
}

# Extract an Adminer version string from a PHP file, if one can be found
detect_version() {
    local f="$1" v=""
    v="$(grep -oE "Adminer[^0-9]{0,40}[0-9]+\.[0-9]+\.[0-9]+" "$f" 2>/dev/null \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
    if [ -z "$v" ]; then
        v="$(grep -oE "VERSION[^=]{0,20}=[^0-9]{0,5}[0-9]+\.[0-9]+\.[0-9]+" "$f" 2>/dev/null \
            | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
    fi
    printf '%s' "$v"
}

[ -d "$INSTALL_ROOT" ] || die "install root $INSTALL_ROOT not found"

# 1. Locate Adminer core files (the ones defining adminer_object, not plugins)
mapfile -t CANDIDATES < <(grep -rlI --include='*.php' 'function adminer_object' "$INSTALL_ROOT" 2>/dev/null | sort -u || true)
[ "${#CANDIDATES[@]}" -gt 0 ] || die "no Adminer core files found under $INSTALL_ROOT"

# Resolve symlinks and deduplicate real targets
mapfile -t TARGETS < <(for f in "${CANDIDATES[@]}"; do readlink -f "$f"; done | sort -u)

VULNERABLE=()
for t in "${TARGETS[@]}"; do
    ver="$(detect_version "$t")"
    if [ -z "$ver" ]; then
        log "WARN: could not detect version of $t; treating as vulnerable"
        VULNERABLE+=("$t")
    elif version_lt "$ver" "$FIXED_VERSION"; then
        log "Found vulnerable Adminer $ver at $t"
        VULNERABLE+=("$t")
    else
        log "Adminer $ver at $t is already fixed"
    fi
done

if [ "${#VULNERABLE[@]}" -eq 0 ]; then
    log "Nothing to remediate"
    exit 0
fi

# 2. Download the fixed release and validate it before touching anything
log "Downloading Adminer ${NEW_VERSION} from upstream"
curl -fsSL --retry 3 --retry-delay 2 -o "$TMP_FILE" "$DOWNLOAD_URL" \
    || die "download failed: $DOWNLOAD_URL"

[ -s "$TMP_FILE" ] || die "downloaded file is empty"
grep -q 'function adminer_object' "$TMP_FILE" || die "downloaded file does not look like Adminer"
if command -v php >/dev/null 2>&1; then
    php -l "$TMP_FILE" >/dev/null 2>&1 || die "downloaded file failed PHP syntax check"
fi

# 3. Back up and replace vulnerable files in place (keeps inode, perms and symlink targets)
mkdir -p "$BACKUP_DIR"
for t in "${VULNERABLE[@]}"; do
    log "Backing up $t"
    cp -p "$t" "$BACKUP_DIR/$(echo "$t" | tr '/' '_')"

    log "Replacing $t with Adminer ${NEW_VERSION}"
    cat "$TMP_FILE" > "$t"
    chmod 0644 "$t"

    if command -v php >/dev/null 2>&1 && ! php -l "$t" >/dev/null 2>&1; then
        log "PHP check failed on $t, restoring backup"
        cp -p "$BACKUP_DIR/$(echo "$t" | tr '/' '_')" "$t"
        die "replacement of $t was reverted"
    fi
done

# 4. Verify the result
for t in "${VULNERABLE[@]}"; do
    ver="$(detect_version "$t")"
    if [ -n "$ver" ] && version_lt "$ver" "$FIXED_VERSION"; then
        die "verification failed: $t still reports $ver"
    fi
done

log "Remediation complete. Backups stored in $BACKUP_DIR"
exit 0