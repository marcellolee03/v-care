#!/bin/bash
set -euo pipefail

# Generate strong random passwords for the ActiveMQ web console users.
ADMIN_PASS="$(openssl rand -hex 16)"
USER_PASS="$(openssl rand -hex 16)"

# Collect candidate Jetty realm files from known ActiveMQ installations.
realm_files=()
for home in /opt/activemq /opt/apache-activemq-*; do
    realm="$home/conf/jetty-realm.properties"
    [ -f "$realm" ] && realm_files+=("$realm")
done

# Fall back to searching under /opt if the usual paths are not present.
if [ ${#realm_files[@]} -eq 0 ]; then
    while IFS= read -r f; do
        realm_files+=("$f")
    done < <(find /opt -type f -name 'jetty-realm.properties' 2>/dev/null)
fi

processed_realms=""
for realm in "${realm_files[@]}"; do
    if command -v realpath >/dev/null 2>&1; then
        real_realm="$(realpath "$realm")"
    else
        real_realm="$realm"
    fi

    case " $processed_realms " in
        *" $real_realm "*) continue ;;
    esac
    processed_realms="$processed_realms $real_realm"

    tmp="$(mktemp /tmp/jetty-realm.XXXXXX)"
    awk -v ap="$ADMIN_PASS" -v up="$USER_PASS" '
        /^[[:space:]]*admin[[:space:]]*:/ {
            n = split($0, parts, ",")
            roles = ""
            for (i = 2; i <= n; i++) {
                r = parts[i]
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", r)
                gsub(/\r/, "", r)
                if (r != "") {
                    if (roles != "") roles = roles ", "
                    roles = roles r
                }
            }
            if (roles == "") roles = "admin"
            print "admin: " ap ", " roles
            next
        }
        /^[[:space:]]*user[[:space:]]*:/ {
            n = split($0, parts, ",")
            roles = ""
            for (i = 2; i <= n; i++) {
                r = parts[i]
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", r)
                gsub(/\r/, "", r)
                if (r != "") {
                    if (roles != "") roles = roles ", "
                    roles = roles r
                }
            }
            if (roles == "") roles = "user"
            print "user: " up ", " roles
            next
        }
        { print }
    ' "$real_realm" > "$tmp"

    # Overwrite in place so ownership and permissions are preserved.
    cat "$tmp" > "$real_realm"
    rm -f "$tmp"
done