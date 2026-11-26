#!/bin/bash
set -euo pipefail

TS="$(date +%Y%m%d%H%M%S 2>/dev/null || echo manual)"

CONF_DIRS=""

add_conf_dir() {
    local dir="$1" real
    [ -n "${dir:-}" ] || return 0
    [ -d "$dir" ] || return 0
    real="$(readlink -f "$dir" 2>/dev/null || printf '%s' "$dir")"
    case " $CONF_DIRS " in
        *" $real "*) ;;
        *) CONF_DIRS="${CONF_DIRS} ${real}" ;;
    esac
}

# Known ActiveMQ configuration locations
add_conf_dir "/opt/activemq/conf"
add_conf_dir "/opt/apache-activemq-5.11.1/conf"

# Discover additional ActiveMQ configuration directories if the install tree is duplicated
for root in /opt /usr/local /var/lib /srv; do
    [ -d "$root" ] || continue
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        add_conf_dir "$(dirname "$f")"
    done < <(find "$root" -maxdepth 6 -type f -name activemq.xml 2>/dev/null || true)
done

disable_web_console_in() {
    local conf="$1" jf
    jf="${conf}/jetty.xml"
    [ -f "$jf" ] || return 0

    cp -a "$jf" "${jf}.bak.${TS}" 2>/dev/null || true

    # Remove the Jetty web console listener.  The ActiveMQ broker does not
    # depend on this listener, and removing it prevents the admin/API webapps
    # from offering HTTP Basic Authentication over cleartext HTTP on 8161.
    cat > "$jf" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<beans xmlns="http://www.springframework.org/schema/beans">
    <!-- Web console disabled to prevent cleartext HTTP Basic Authentication. -->
</beans>
EOF
}

for conf in $CONF_DIRS; do
    disable_web_console_in "$conf"
done