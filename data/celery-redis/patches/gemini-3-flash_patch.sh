```bash
#!/bin/bash

# Set strict error handling
set -euo pipefail

# Verify root privileges
if [[ "${EUID}" -ne 0 ]]; then
    exit 1
fi

# Define configuration path for Debian-based Redis
REDIS_CONF="/etc/redis/redis.conf"

# Exit silently if configuration does not exist
if [[ ! -f "$REDIS_CONF" ]]; then
    exit 0
fi

# Idempotency check: verify if 'requirepass' is already active (uncommented)
if ! grep -qE "^\s*requirepass\s+" "$REDIS_CONF"; then
    # Generate a secure 32-character password using /dev/urandom
    NEW_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)

    # Use sed to uncomment and update 'requirepass' if the template exists, 
    # otherwise append to the end of the file.
    if grep -q "^# requirepass " "$REDIS_CONF"; then
        sed -i "s/^# requirepass .*/requirepass $NEW_PASS/" "$REDIS_CONF"
    else
        echo "requirepass $NEW_PASS" >> "$REDIS_CONF"
    fi

    # Ensure restrictive permissions on config file containing the new secret
    chmod 600 "$REDIS_CONF"

    # Restart service if systemd is present and service is active
    if systemctl is-active --quiet redis-server 2>/dev/null; then
        systemctl restart redis-server >/dev/null 2>&1
    fi
fi
```