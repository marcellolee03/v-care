#!/bin/bash
set -euo pipefail
umask 077

ADMIN_PW="$(openssl rand -hex 32)"
USER_PW="$(openssl rand -hex 32)"
SEEN=""

update_realm_file() {
  local file="$1"
  local real tmp

  [ -f "$file" ] || return 0

  real="$(readlink -f "$file" 2>/dev/null || printf '%s' "$file")"
  case " $SEEN " in
    *" $real "*) return 0 ;;
  esac
  SEEN="$SEEN $real"

  cp -p "$file" "${file}.bak" 2>/dev/null || true
  tmp="$(mktemp /tmp/jetty-realm.XXXXXX)"

  awk -v admin_pw="$ADMIN_PW" -v user_pw="$USER_PW" '
    {
      line = $0

      if (line ~ /^[[:space:]]*#/ || line ~ /^[[:space:]]*$/) {
        print line
        next
      }

      colon = index(line, ":")
      if (colon == 0) {
        print line
        next
      }

      name = substr(line, 1, colon - 1)
      rest = substr(line, colon + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)

      if (name == "admin" || name == "user") {
        sub(/^[[:space:]]*/, "", rest)
        comma = index(rest, ",")
        roles = (comma > 0) ? substr(rest, comma) : ""

        if (name == "admin") {
          printf("admin: %s%s\n", admin_pw, roles)
        } else {
          printf("user: %s%s\n", user_pw, roles)
        }
      } else {
        print line
      }
    }
  ' "$file" > "$tmp"

  if grep -Eq '^[[:space:]]*(admin|user)[[:space:]]*:' "$tmp"; then
    cat "$tmp" > "$file"
  fi

  rm -f "$tmp"
}

update_realm_file /opt/activemq/conf/jetty-realm.properties
update_realm_file /opt/apache-activemq-5.11.1/conf/jetty-realm.properties

if command -v find >/dev/null 2>&1; then
  while IFS= read -r realm_file; do
    update_realm_file "$realm_file"
  done < <(find /opt -maxdepth 5 -type f -name 'jetty-realm.properties' 2>/dev/null)
fi