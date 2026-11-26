#!/bin/bash
# Remediation for CVE-2021-41773 / CVE-2021-42013 style path traversal in Apache HTTP Server 2.4.49.
# Strategy: config_change. The root directory is denied by default, so traversal to files
# outside the document root (including /bin/sh via the cgi-bin alias) is refused.
# No package manager or network access to upstream is assumed.

set -uo pipefail

export DEBIAN_FRONTEND=noninteractive

CONF_DIR="/usr/local/apache2/conf"
CONF="${CONF_DIR}/httpd.conf"
HTTPD_BIN="/usr/local/apache2/bin/httpd"
TS="$(date +%Y%m%d%H%M%S)"
BAK="${CONF}.bak.${TS}"

log() { echo "[remediate] $*"; }
fail() { echo "[remediate] ERROR: $*" >&2; exit 1; }

[ -f "${CONF}" ] || fail "Apache config not found at ${CONF}"
command -v perl >/dev/null 2>&1 || fail "perl is required for the config edit"

# Back up the current configuration so it can be restored if validation fails.
cp -p "${CONF}" "${BAK}" || fail "could not create backup at ${BAK}"
log "backup written to ${BAK}"

# Ensure the root directory is denied. If a <Directory /> block exists, replace its
# Require directives with 'Require all denied'. Otherwise append a new block.
if grep -Eq '<Directory[[:space:]]+"?/"?[[:space:]]*>' "${CONF}"; then
    log "updating existing <Directory /> block"
    perl -0777 -i -pe '
        s{(<Directory[ \t]+"?/"?[ \t]*>)(.*?)(</Directory>)}{
            my ($o, $b, $c) = ($1, $2, $3);
            $b =~ s/^[ \t]*Require[ \t].*\n//mg;
            "$o\n    Require all denied\n$b$c"
        }segi;
    ' "${CONF}" || { cp -p "${BAK}" "${CONF}"; fail "failed to edit <Directory /> block"; }
else
    log "no <Directory /> block found; appending one"
    cat >> "${CONF}" <<'EOF'

# Deny access to the whole filesystem by default (CVE-2021-41773 mitigation)
<Directory />
    AllowOverride None
    Require all denied
</Directory>
EOF
fi

# Verify the directive is now present inside the root Directory block.
if ! perl -0777 -ne 'exit(/<Directory[ \t]+"?\/"?[ \t]*>(?:(?!<\/Directory>).)*Require[ \t]+all[ \t]+denied(?:(?!<\/Directory>).)*<\/Directory>/s ? 0 : 1)' "${CONF}"; then
    cp -p "${BAK}" "${CONF}"
    fail "verification failed; original configuration restored"
fi
log "root directory is now 'Require all denied'"

# Validate the configuration syntax if httpd is available. Restore on failure.
if [ -x "${HTTPD_BIN}" ]; then
    if ! "${HTTPD_BIN}" -t -f "${CONF}" >/tmp/httpd-test.$$ 2>&1; then
        cat /tmp/httpd-test.$$ >&2
        rm -f /tmp/httpd-test.$$
        cp -p "${BAK}" "${CONF}"
        fail "httpd -t failed; original configuration restored"
    fi
    rm -f /tmp/httpd-test.$$
    log "configuration syntax check passed"
else
    log "httpd binary not found at ${HTTPD_BIN}; skipping syntax check"
fi

log "remediation complete. The container restart will apply the change."
exit 0