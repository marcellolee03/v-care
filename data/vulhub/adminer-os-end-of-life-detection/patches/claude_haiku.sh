#!/bin/bash
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

LOG=/var/log/remediate-eol.log
log() { echo "[$(date -u +%FT%TZ)] $*" | tee -a "$LOG" 2>/dev/null || echo "[$(date -u +%FT%TZ)] $*"; }
die() { log "ERROR: $*"; exit 1; }

POLICY=/usr/sbin/policy-rc.d
cleanup() {
    rm -f "$POLICY"
    apt-get clean >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Never start or stop services during package operations (no init system, PID 1 is the app).
printf '#!/bin/sh\nexit 101\n' > "$POLICY" && chmod 755 "$POLICY" || die "cannot create policy-rc.d"

# Only act on the EOL Debian 11 base.
[ -r /etc/os-release ] || die "/etc/os-release missing"
. /etc/os-release
if [ "${VERSION_CODENAME:-}" != "bullseye" ]; then
    log "Base is ${VERSION_CODENAME:-unknown}, not bullseye. Nothing to do."
    exit 0
fi

# Back up apt sources and the adminer/apache/php configuration state.
BK="/root/eol-backup-$(date +%s)"
mkdir -p "$BK" || die "cannot create backup dir"
cp -a /etc/apt/sources.list "$BK/" 2>/dev/null || true
cp -a /etc/apt/sources.list.d "$BK/" 2>/dev/null || true
cp -a /etc/apt/preferences.d "$BK/" 2>/dev/null || true
cp -a /etc/apache2 "$BK/" 2>/dev/null || true
cp -a /usr/local/etc/php "$BK/" 2>/dev/null || true
log "Backup written to $BK"

# Replace bullseye sources with bookworm sources.
mkdir -p /etc/apt/sources.list.d
find /etc/apt/sources.list.d -maxdepth 1 -type f -exec rm -f {} +
cat > /etc/apt/sources.list <<'EOF'
deb http://deb.debian.org/debian bookworm main contrib
deb http://deb.debian.org/debian bookworm-updates main contrib
deb http://security.debian.org/debian-security bookworm-security main contrib
EOF

log "Updating package lists for bookworm"
apt-get update || die "apt-get update failed"

APT_OPTS=(-y -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef)

log "Upgrading packages to bookworm"
apt-get "${APT_OPTS[@]}" upgrade || die "apt-get upgrade failed"
apt-get "${APT_OPTS[@]}" full-upgrade || die "apt-get full-upgrade failed"
apt-get -y autoremove --purge || log "WARN: autoremove reported an error"

# Source packages built against bullseye (for example an official php image)
# may need libssl1.1, which bookworm no longer ships. Provide it from bullseye
# at low priority so nothing else is pulled from bullseye.
missing_libs() {
    for f in /usr/local/bin/php /usr/lib/apache2/modules/*.so /usr/local/lib/php/extensions/*/*.so; do
        [ -f "$f" ] || continue
        ldd "$f" 2>/dev/null | grep 'not found' || true
    done | sort -u
}

MISSING="$(missing_libs)"
if [ -n "$MISSING" ]; then
    log "Missing shared libraries after upgrade:"
    log "$MISSING"
    if echo "$MISSING" | grep -Eq 'libssl\.so\.1\.1|libcrypto\.so\.1\.1'; then
        log "Installing libssl1.1 from bullseye at low priority"
        echo "deb http://deb.debian.org/debian bullseye main" > /etc/apt/sources.list.d/bullseye-compat.list
        printf 'Package: *\nPin: release n=bullseye\nPin-Priority: 100\n' > /etc/apt/preferences.d/bullseye-compat
        apt-get update || die "apt-get update (compat) failed"
        apt-get "${APT_OPTS[@]}" install libssl1.1 || die "libssl1.1 install failed"
        rm -f /etc/apt/sources.list.d/bullseye-compat.list
        apt-get update >/dev/null 2>&1 || true
    fi
    MISSING="$(missing_libs)"
    [ -z "$MISSING" ] || die "unresolved missing libraries: $MISSING"
fi

# Verify the stack is still usable. Services will be started by the restart.
if command -v apache2ctl >/dev/null 2>&1; then
    apache2ctl -t >/dev/null 2>&1 || die "apache configuration test failed"
fi
if command -v php >/dev/null 2>&1; then
    php -v >/dev/null 2>&1 || die "php binary failed to run"
fi
[ -f /var/www/html/index.php ] || log "WARN: adminer index.php not found in /var/www/html"

NEW_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
log "Base codename is now: ${NEW_CODENAME}"
[ "$NEW_CODENAME" = "bookworm" ] || die "OS codename is still ${NEW_CODENAME}"

log "Remediation complete. Container restart will load the upgraded stack."
exit 0