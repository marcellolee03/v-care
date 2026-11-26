#!/usr/bin/env bash
# Remediation: ActiveMQ web console (Jetty, port 8161) ships with default credentials
# admin:admin and user:user in conf/jetty-realm.properties. Replace those passwords
# with random values, keep the existing role assignments, and keep the broker running.

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

INSTALL_ROOT="/opt/activemq"
ALT_ROOT="/opt/apache-activemq-5.11.1"
CRED_FILE="/root/.activemq-web-credentials"

log() { printf '[remediate] %s\n' "$*"; }
die() { printf '[remediate] ERROR: %s\n' "$*" >&2; exit 1; }

gen_password() {
    local pw=""
    if command -v openssl >/dev/null 2>&1; then
        pw="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 24)"
    fi
    if [ "${#pw}" -lt 24 ]; then
        pw="$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24)"
    fi
    [ "${#pw}" -eq 24 ] || die "could not generate a password"
    printf '%s' "$pw"
}

# Locate the web console realm file.
REALM_FILE=""
for root in "$INSTALL_ROOT" "$ALT_ROOT"; do
    if [ -d "$root" ]; then
        candidate="$(find "$(readlink -f "$root")" -name 'jetty-realm.properties' -type f 2>/dev/null | head -n 1 || true)"
        if [ -n "$candidate" ]; then
            REALM_FILE="$candidate"
            break
        fi
    fi
done
[ -n "$REALM_FILE" ] || die "jetty-realm.properties not found under $INSTALL_ROOT or $ALT_ROOT"
[ -w "$REALM_FILE" ] || die "realm file is not writable: $REALM_FILE"
log "realm file: $REALM_FILE"

ADMIN_PW="$(gen_password)"
USER_PW="$(gen_password)"

BACKUP="${REALM_FILE}.bak.$(date +%Y%m%d%H%M%S)"
cp -p "$REALM_FILE" "$BACKUP"
log "backup written to $BACKUP"

TMP_FILE="$(mktemp "${REALM_FILE}.XXXXXX")"
chmod --reference="$REALM_FILE" "$TMP_FILE" 2>/dev/null || chmod 600 "$TMP_FILE"

# Rewrite the password of the admin and user accounts, keeping their roles.
# Comments and other accounts are left untouched.
awk -v ap="$ADMIN_PW" -v up="$USER_PW" '
BEGIN { FS = ":"; seen_admin = 0; seen_user = 0 }
{
    line = $0
    if (line ~ /^[[:space:]]*#/ || line !~ /:/) { print line; next }

    name = substr(line, 1, index(line, ":") - 1)
    gsub(/^[ \t]+|[ \t]+$/, "", name)
    rest = substr(line, index(line, ":") + 1)

    roles = ""
    if (index(rest, ",") > 0) {
        roles = substr(rest, index(rest, ","))
    }

    if (name == "admin") {
        print "admin: " ap roles
        seen_admin = 1
    } else if (name == "user") {
        print "user: " up roles
        seen_user = 1
    } else {
        print line
    }
}
END {
    if (!seen_admin) print "admin: " ap ", admin"
    if (!seen_user)  print "user: " up ", user"
}
' "$REALM_FILE" > "$TMP_FILE"

# Verify the result before replacing the original.
[ -s "$TMP_FILE" ] || die "generated realm file is empty; original left untouched"
if grep -Eq '^[[:space:]]*(admin|user)[[:space:]]*:[[:space:]]*(admin|user)([[:space:]]*,|[[:space:]]*$)' "$TMP_FILE"; then
    rm -f "$TMP_FILE"
    die "default credentials still present after rewrite; original left untouched"
fi
grep -Eq '^[[:space:]]*admin[[:space:]]*:' "$TMP_FILE" || die "admin entry missing after rewrite"

mv -f "$TMP_FILE" "$REALM_FILE"
log "web console passwords for admin and user were replaced"

# Store the new credentials for the operator, readable by root only.
umask 077
{
    echo "ActiveMQ web console credentials (generated $(date -u +%FT%TZ))"
    echo "realm_file=$REALM_FILE"
    echo "admin_user=admin"
    echo "admin_password=$ADMIN_PW"
    echo "user_user=user"
    echo "user_password=$USER_PW"
} > "$CRED_FILE"
chmod 600 "$CRED_FILE"
log "new credentials stored in $CRED_FILE (mode 600)"

# Sanity check: the file still parses as key: value lines with at least one entry.
awk -F: '!/^[[:space:]]*#/ && NF>0 && $1 ~ /[^[:space:]]/ { n++ } END { exit (n>0 ? 0 : 1) }' "$REALM_FILE" \
    || die "realm file has no valid entries after rewrite"

log "remediation complete; the container restart will apply the new realm"
exit 0