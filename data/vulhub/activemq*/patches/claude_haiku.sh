#!/bin/bash
# Remediation: replace default ActiveMQ web console credentials (admin/admin, user/user)
# with randomly generated passwords. Roles are preserved. Takes effect on container restart.

set -u

export DEBIAN_FRONTEND=noninteractive

INSTALL_ROOT="/opt/activemq"
CONF_DIR="${INSTALL_ROOT}/conf"
REALM_FILE="${CONF_DIR}/jetty-realm.properties"
CRED_FILE="/root/activemq-webconsole-credentials.txt"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

log()  { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
fail() { log "ERROR: $*"; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "must run as root"

# Locate the web console realm file. Fall back to a search if the default path differs.
if [ ! -f "$REALM_FILE" ]; then
    FOUND="$(find "$INSTALL_ROOT" /opt -maxdepth 4 -name 'jetty-realm.properties' 2>/dev/null | head -n 1)"
    [ -n "$FOUND" ] || fail "jetty-realm.properties not found under ${INSTALL_ROOT}"
    REALM_FILE="$FOUND"
    CONF_DIR="$(dirname "$REALM_FILE")"
fi
log "Using realm file: ${REALM_FILE}"

# Back up the original file once per run.
BACKUP="${REALM_FILE}.bak.${TIMESTAMP}"
cp -p "$REALM_FILE" "$BACKUP" || fail "backup failed"
log "Backup written to ${BACKUP}"

# Generate strong passwords. Base64 without '/', '+', '=' avoids characters that
# are special in properties files and in comma-separated role lists.
gen_pw() {
    openssl rand -base64 24 | tr -d '/+=\n' | cut -c1-24
}
ADMIN_PW="$(gen_pw)"
USER_PW="$(gen_pw)"
[ -n "$ADMIN_PW" ] && [ -n "$USER_PW" ] || fail "password generation failed"

TMP_FILE="$(mktemp "${CONF_DIR}/.jetty-realm.XXXXXX")" || fail "mktemp failed"

# Rewrite matching entries, keeping their roles. Append any missing account.
awk -v admin_pw="$ADMIN_PW" -v user_pw="$USER_PW" '
BEGIN { seen_admin = 0; seen_user = 0 }
{
    line = $0
    if (line ~ /^[[:space:]]*admin[[:space:]]*:/) {
        seen_admin = 1
        rest = line
        sub(/^[[:space:]]*admin[[:space:]]*:[[:space:]]*[^,[:space:]]*/, "", rest)
        if (rest == "") rest = ", admin"
        print "admin: " admin_pw rest
        next
    }
    if (line ~ /^[[:space:]]*user[[:space:]]*:/) {
        seen_user = 1
        rest = line
        sub(/^[[:space:]]*user[[:space:]]*:[[:space:]]*[^,[:space:]]*/, "", rest)
        if (rest == "") rest = ", user"
        print "user: " user_pw rest
        next
    }
    print line
}
END {
    if (!seen_admin) print "admin: " admin_pw ", admin"
    if (!seen_user)  print "user: " user_pw ", user"
}
' "$REALM_FILE" > "$TMP_FILE" || { rm -f "$TMP_FILE"; fail "rewrite failed"; }

# Preserve ownership and mode of the original file.
chown --reference="$REALM_FILE" "$TMP_FILE" 2>/dev/null || true
chmod --reference="$REALM_FILE" "$TMP_FILE" 2>/dev/null || chmod 640 "$TMP_FILE"
mv -f "$TMP_FILE" "$REALM_FILE" || fail "could not replace realm file"

# Verify the default credentials are gone and the new ones are present.
if grep -Eq '^[[:space:]]*admin[[:space:]]*:[[:space:]]*admin([[:space:]]*,|[[:space:]]*$)' "$REALM_FILE"; then
    fail "default admin credential still present after edit"
fi
if grep -Eq '^[[:space:]]*user[[:space:]]*:[[:space:]]*user([[:space:]]*,|[[:space:]]*$)' "$REALM_FILE"; then
    fail "default user credential still present after edit"
fi
grep -Fq "admin: ${ADMIN_PW}" "$REALM_FILE" || fail "admin entry verification failed"
grep -Fq "user: ${USER_PW}" "$REALM_FILE" || fail "user entry verification failed"

# Store the new credentials for the operator, readable by root only.
umask 077
{
    echo "ActiveMQ web console credentials (generated ${TIMESTAMP})"
    echo "Console: http://<host>:8161/admin/"
    echo "admin: ${ADMIN_PW}"
    echo "user: ${USER_PW}"
} > "$CRED_FILE" || fail "could not write credential file"
chmod 600 "$CRED_FILE"

log "Default web console credentials replaced."
log "New credentials stored in ${CRED_FILE} (mode 600)."
log "Restart the container to apply the change."
exit 0