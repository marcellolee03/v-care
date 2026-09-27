```bash
#!/bin/bash
set -euo pipefail

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Redis configuration file location
REDIS_CONF="/etc/redis/redis.conf"

# Verify Redis configuration file exists
if [ ! -f "$REDIS_CONF" ]; then
    echo "Error: Redis configuration file not found at $REDIS_CONF" >&2
    exit 1
fi

# Check if password is already set
if grep -q "^requirepass" "$REDIS_CONF"; then
    # Password already configured, exit silently
    exit 0
fi

# Generate a secure random password (32 characters)
REDIS_PASSWORD=$(tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c 32)

# Add requirepass directive to Redis configuration
if sed -i "/^# requirepass/a requirepass $REDIS_PASSWORD" "$REDIS_CONF"; then
    # Restart Redis service to apply changes
    systemctl restart redis-server 2>/dev/null || service redis-server restart 2>/dev/null
else
    echo "Error: Failed to modify Redis configuration" >&2
    exit 1
fi
```