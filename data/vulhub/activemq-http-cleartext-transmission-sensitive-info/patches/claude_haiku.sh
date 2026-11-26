#!/usr/bin/env bash
set -euo pipefail

# Remediation: bind the ActiveMQ web console (Jetty, port 8161) to the loopback
# interface so the Basic Auth endpoints are no longer reachable through the
# published port. OpenWire and the other broker connectors are not touched.

BACKUP_DIR="/var/backups/remediation"
TARGET_HOST="127.0.0.1"

log() { printf '[remediate] %s\n' "$*"; }
die() { printf '[remediate] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "must run as root"

# Locate jetty.xml that defines the web console.
JETTY_XML=""
for f in /opt/activemq/conf/jetty.xml /opt/apache-activemq-5.11.1/conf/jetty.xml; do
    if [ -f "$f" ]; then
        JETTY_XML="$f"
        break
    fi
done

if [ -z "$JETTY_XML" ]; then
    JETTY_XML="$(find /opt /srv /home /root /usr/local -type f -name jetty.xml -path '*conf*' 2>/dev/null | head -n 1 || true)"
fi
[ -n "$JETTY_XML" ] && [ -f "$JETTY_XML" ] || die "jetty.xml not found"
log "using $JETTY_XML"

mkdir -p "$BACKUP_DIR"
BACKUP="$BACKUP_DIR/jetty.xml.$(date +%Y%m%d%H%M%S).bak"
cp -p "$JETTY_XML" "$BACKUP"
log "backup written to $BACKUP"

TMP="$(mktemp /tmp/jetty.xml.XXXXXX)"
trap 'rm -f "$TMP"' EXIT

# Rewrite the host property inside the WebConsolePort bean only.
# If the bean has no host property, one is inserted before its closing tag.
awk -v host="$TARGET_HOST" '
BEGIN { inb = 0; hosted = 0; found = 0 }
{
    if (!found && $0 ~ /class="org\.apache\.activemq\.web\.WebConsolePort"/) {
        inb = 1; found = 1
        print
        next
    }
    if (inb) {
        if ($0 ~ /<property[[:space:]]+name="host"/) {
            sub(/value="[^"]*"/, "value=\"" host "\"")
            hosted = 1
            print
            next
        }
        if ($0 ~ /<\/bean>/) {
            if (!hosted) {
                print "        <property name=\"host\" value=\"" host "\"/>"
            }
            inb = 0
        }
    }
    print
}
END {
    if (!found) exit 3
}' "$JETTY_XML" > "$TMP" || die "WebConsolePort bean not found in $JETTY_XML"

grep -q "name=\"host\" value=\"$TARGET_HOST\"" "$TMP" \
    || die "host binding not present after rewrite"

# Basic sanity: bean tags must stay balanced.
OPEN_CNT="$(grep -c '<bean[[:space:]>]' "$TMP" || true)"
CLOSE_CNT="$(grep -c '</bean>' "$TMP" || true)"
[ "$OPEN_CNT" -eq "$CLOSE_CNT" ] || die "bean tags unbalanced after rewrite; aborting"

if cmp -s "$TMP" "$JETTY_XML"; then
    log "web console already bound to $TARGET_HOST"
else
    cat "$TMP" > "$JETTY_XML"
    log "web console host set to $TARGET_HOST"
fi

log "remediation complete; the container must be restarted to apply the change"
exit 0