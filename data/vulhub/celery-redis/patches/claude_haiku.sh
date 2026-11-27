#!/bin/sh
set -eu
export DEBIAN_FRONTEND=noninteractive

MARK=/etc/redis/.remediated-requirepass
PWDIR=/etc/redis
PWFILE=/etc/redis/requirepass
WRAP_MARKER='REDIS-REQUIREPASS-WRAPPER'

log() { echo "[remediate] $*"; }
die() { echo "[remediate] ERROR: $*" >&2; exit 1; }

if [ -f "$MARK" ]; then
    log "Already remediated; nothing to do."
    exit 0
fi

BIN=$(command -v redis-server 2>/dev/null || true)
[ -n "$BIN" ] || die "redis-server binary not found in PATH"

REAL=$(readlink -f "$BIN")
[ -f "$REAL" ] || die "cannot resolve redis-server binary: $REAL"
ORIG="${REAL}.orig"

# Determine whether a wrapper from a previous run already sits in place.
if grep -q "$WRAP_MARKER" "$REAL" 2>/dev/null; then
    [ -x "$ORIG" ] || die "wrapper present but original binary missing: $ORIG"
    log "Wrapper already present at $REAL."
else
    [ -x "$REAL" ] || die "redis-server binary not executable: $REAL"
    if [ -e "$ORIG" ]; then
        die "$ORIG already exists but $REAL is not a wrapper; refusing to overwrite"
    fi
    mv "$REAL" "$ORIG"
    log "Moved original binary to $ORIG"
fi

# Generate a random password and store it.
mkdir -p "$PWDIR"
PW=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 40)
[ -n "$PW" ] || die "failed to generate password"

TMP="${PWFILE}.tmp"
printf '%s\n' "$PW" > "$TMP"
if getent group redis >/dev/null 2>&1; then
    chown root:redis "$TMP"
    chmod 640 "$TMP"
else
    chmod 600 "$TMP"
fi
mv "$TMP" "$PWFILE"
log "Password written to $PWFILE"

# Install a wrapper that always starts redis-server with --requirepass.
# This applies on every start, including the original entrypoint/command
# after 'docker restart'. Command-line options also work when the user
# passes their own config file.
cat > "$REAL" <<'WRAP'
#!/bin/sh
# REDIS-REQUIREPASS-WRAPPER
PWFILE=/etc/redis/requirepass
ORIG=@ORIG@
if [ -r "$PWFILE" ]; then
    PW=$(cat "$PWFILE")
    exec "$ORIG" --requirepass "$PW" "$@"
fi
echo "redis wrapper: cannot read $PWFILE" >&2
exit 1
WRAP
sed -i "s|@ORIG@|$ORIG|" "$REAL"
chmod 755 "$REAL"
log "Installed requirepass wrapper at $REAL"

# Sanity check the wrapper resolves and the original binary runs.
"$ORIG" --version >/dev/null 2>&1 || die "original redis-server does not execute"
[ -x "$REAL" ] || die "wrapper not executable"

touch "$MARK"
log "Done. Container must be restarted for the password to take effect."
exit 0