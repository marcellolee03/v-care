```bash
#!/bin/bash
set -euo pipefail

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
    exit 1
fi

readonly REDIS_CONF="/etc/redis/redis.conf"

# Exit silently if Redis configuration does not exist
[[ -f "$REDIS_CONF" ]] || exit 0

# Idempotency: Check if 'requirepass' is already active
if ! grep -q "^\s*requirepass\s\+" "$REDIS_CONF"; then
    # Generate a secure 32-character alphanumeric password
    # LC_ALL=C ensures tr handles the byte stream correctly
    PASS=$(head /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 32)

    # Surgical replacement: If a commented example exists, replace it; otherwise, append
    if grep -q "^\s*#\s*requirepass\s\+" "$REDIS_CONF"; then
        sed -i "s/^\s*#\s*requirepass\s\+.*/requirepass $PASS/" "$REDIS_CONF"
    else
        printf "\n# Security Hardening: Added by mitigation script\nrequirepass %s\n" "$PASS" >> "$REDIS_CONF"
    fi

    # Restrict file permissions as it now contains a plaintext password
    chmod 600 "$REDIS_CONF"

    # Restart the service to apply changes using systemd or sysvinit
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart redis-server >/dev/null 2>&1 || true
    elif [[ -x /etc/init.d/redis-server ]]; then
        /etc/init.d/redis-server restart >/dev/null 2>&1 || true
    fi
fi
```