#!/bin/bash

set -euo pipefail

# Root check
if [ "$EUID" -ne 0 ]; then 
    echo "This script must be run as root" >&2
    exit 1
fi

REDIS_CONF="/etc/redis/redis.conf"
BACKUP_SUFFIX=".backup.$(date +%Y%m%d_%H%M%S)"

# Verify Redis configuration exists
if [ ! -f "$REDIS_CONF" ]; then
    echo "Redis configuration not found at $REDIS_CONF" >&2
    exit 1
fi

# Create backup
cp "$REDIS_CONF" "$REDIS_CONF$BACKUP_SUFFIX"

# Generate a random password (32 chars)
REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d '\n' | head -c 32)

# Update requirepass directive
if grep -q "^requirepass" "$REDIS_CONF"; then
    # Replace existing password
    sed -i "s/^requirepass.*/requirepass $REDIS_PASSWORD/" "$REDIS_CONF"
else
    # Add password configuration
    echo "requirepass $REDIS_PASSWORD" >> "$REDIS_CONF"
fi

# Ensure Redis is bound only to localhost if not already configured
if ! grep -q "^bind 127.0.0.1" "$REDIS_CONF"; then
    if grep -q "^bind " "$REDIS_CONF"; then
        # Comment out existing bind directives
        sed -i '/^bind /s/^/# /' "$REDIS_CONF"
    fi
    echo "bind 127.0.0.1" >> "$REDIS_CONF"
fi

# Restart Redis service
if systemctl is-active --quiet redis-server; then
    systemctl restart redis-server >/dev/null 2>&1 || {
        echo "Failed to restart Redis service" >&2
        exit 1
    }
fi

# Save password to secure location
echo "Redis password: $REDIS_PASSWORD" > /root/redis_password.txt
chmod 600 /root/redis_password.txt