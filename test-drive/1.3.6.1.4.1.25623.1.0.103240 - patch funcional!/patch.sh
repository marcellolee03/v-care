#!/bin/bash
set -eu

REALM_FILE=""
for candidate in \
  "${ACTIVEMQ_BASE:-/opt/activemq}/conf/jetty-realm.properties" \
  "/opt/activemq/conf/jetty-realm.properties" \
  "/opt/apache-activemq-5.11.1/conf/jetty-realm.properties"
do
  if [ -f "$candidate" ]; then
    REALM_FILE="$candidate"
    break
  fi
done

if [ -z "$REALM_FILE" ]; then
  REALM_FILE="$(find /opt -type f -name 'jetty-realm.properties' 2>/dev/null | head -n 1 || true)"
fi

if [ -z "$REALM_FILE" ] || [ ! -f "$REALM_FILE" ]; then
  echo "ERROR: ActiveMQ jetty-realm.properties not found" >&2
  exit 1
fi

NEW_ADMIN_PASS="$(openssl rand -hex 24)"
NEW_USER_PASS="$(openssl rand -hex 24)"

TMP_FILE="$(mktemp /tmp/activemq-jetty-realm.XXXXXX)"
trap 'rm -f "$TMP_FILE"' EXIT
cp "$REALM_FILE" "$TMP_FILE"

sed -E -i \
  -e "s|^[[:space:]]*admin[[:space:]]*:.*$|admin: ${NEW_ADMIN_PASS}, admin|" \
  -e "s|^[[:space:]]*user[[:space:]]*:.*$|user: ${NEW_USER_PASS}, user|" \
  "$TMP_FILE"

grep -Eq '^[[:space:]]*admin[[:space:]]*:' "$TMP_FILE" || \
  printf 'admin: %s, admin\n' "$NEW_ADMIN_PASS" >> "$TMP_FILE"
grep -Eq '^[[:space:]]*user[[:space:]]*:' "$TMP_FILE" || \
  printf 'user: %s, user\n' "$NEW_USER_PASS" >> "$TMP_FILE"

cat "$TMP_FILE" > "$REALM_FILE"

echo "ActiveMQ web console default credentials rotated in $REALM_FILE"