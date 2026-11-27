#!/bin/bash
set -u

PASSWORD='R3dis_NoAuth_Rem3diation_7f4c9a2e'

INFO="$(redis-cli -h 127.0.0.1 -p 6379 INFO server 2>/dev/null || true)"
CONFIG_FILE="$(printf '%s\n' "$INFO" | sed -n 's/^config_file://p' | head -n 1 | tr -d '\r')"
INFO_EXEC="$(printf '%s\n' "$INFO" | sed -n 's/^executable://p' | head -n 1 | tr -d '\r')"

# Find the real Redis executable from the running process first.  INFO's
# executable field can contain a cwd-relative path depending on how it started.
REDIS_EXEC=""
for p in /proc/[0-9]*; do
    [ -d "$p" ] || continue
    exe="$(readlink "$p/exe" 2>/dev/null || true)"
    case "$exe" in
        */redis-server|*/redis-server.real|*/redis-server-*)
            REDIS_EXEC="$exe"
            break
            ;;
    esac
done

if [ -z "${REDIS_EXEC:-}" ] && [ -n "${INFO_EXEC:-}" ] && [ -e "$INFO_EXEC" ]; then
    REDIS_EXEC="$INFO_EXEC"
fi

if [ -z "${REDIS_EXEC:-}" ]; then
    REDIS_EXEC="$(command -v redis-server 2>/dev/null || true)"
fi

# Add requirepass to the active config file and to common Redis config
# locations.  The appended directive is last, so it overrides earlier values.
CONFIGS=""
[ -n "${CONFIG_FILE:-}" ] && CONFIGS="$CONFIG_FILE"
for f in /etc/redis/redis.conf /usr/local/etc/redis/redis.conf /opt/bitnami/redis/etc/redis.conf /etc/redis.conf; do
    [ -f "$f" ] && CONFIGS="${CONFIGS}
${f}"
done

while IFS= read -r conf; do
    [ -n "$conf" ] || continue
    [ -f "$conf" ] || continue

    if [ ! -f "${conf}.redis-noauth.bak" ]; then
        cp -p "$conf" "${conf}.redis-noauth.bak" 2>/dev/null || true
    fi

    if ! grep -qxF "requirepass $PASSWORD" "$conf" 2>/dev/null; then
        printf '\n# Require authentication for Redis\nrequirepass %s\n' "$PASSWORD" >> "$conf" 2>/dev/null || true
    fi
done <<< "$CONFIGS"

# If Redis was started without a config file, or if the entrypoint rewrites
# its config on startup, wrap the redis-server binary so requirepass is always
# supplied on the command line.  Command-line options are parsed after the
# config file and therefore take precedence.
if [ -n "${REDIS_EXEC:-}" ] && [ -e "$REDIS_EXEC" ]; then
    if [ -L "$REDIS_EXEC" ]; then
        resolved="$(readlink -f "$REDIS_EXEC" 2>/dev/null || true)"
        [ -n "$resolved" ] && REDIS_EXEC="$resolved"
    fi

    case "$REDIS_EXEC" in
        *.real)
            REAL="$REDIS_EXEC"
            WRAPPER="${REDIS_EXEC%.real}"
            ;;
        *)
            WRAPPER="$REDIS_EXEC"
            REAL="${REDIS_EXEC}.real"
            ;;
    esac

    if [ ! -f "$WRAPPER" ] || ! grep -q '^# redis-requirepass-wrapper$' "$WRAPPER" 2>/dev/null; then
        if [ "$WRAPPER" = "$REDIS_EXEC" ]; then
            rm -f "$REAL" 2>/dev/null || true
            if ! mv "$WRAPPER" "$REAL" 2>/dev/null; then
                WRAPPER=""
            fi
        fi

        if [ -n "$WRAPPER" ]; then
            cat > "$WRAPPER" <<EOF
#!/bin/sh
# redis-requirepass-wrapper
exec '$REAL' "\$@" --requirepass '$PASSWORD'
EOF
            chmod 0755 "$WRAPPER" 2>/dev/null || true
        fi
    fi
fi

# Protect the currently running instance immediately as well.
redis-cli -h 127.0.0.1 -p 6379 CONFIG SET requirepass "$PASSWORD" >/dev/null 2>&1 || true

exit 0