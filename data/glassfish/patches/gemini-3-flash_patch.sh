```bash
#!/bin/bash

# CVE-2017-1000028: Oracle GlassFish Server Directory Traversal Mitigation
# Mitigation: Restrict the Admin Console listener (port 4848) to the local loopback interface.
# This prevents remote exploitation of the directory traversal vulnerability.

set -euo pipefail

# Verify root privileges
if [ "$(id -u)" -ne 0 ]; then
    exit 1
fi

# Locate GlassFish domain configuration files
# Common installation paths: /opt, /usr/local, or /var/lib
TARGET_CONFIGS=$(find /opt /usr/local /var/lib -name "domain.xml" -path "*/config/domain.xml" 2>/dev/null || true)

for config in $TARGET_CONFIGS; do
    # Only modify if the admin-listener is defined
    if grep -q 'name="admin-listener"' "$config"; then
        # If address attribute exists, update it to 127.0.0.1
        if grep -q 'name="admin-listener"[^>]*address=' "$config"; then
            sed -i '/name="admin-listener"/s/address="[^"]*"/address="127.0.0.1"/' "$config"
        else
            # If address attribute is missing, inject it (GlassFish defaults to 0.0.0.0)
            sed -i 's/name="admin-listener"/name="admin-listener" address="127.0.0.1"/' "$config"
        fi
    fi
done

# Attempt to restart the GlassFish service to apply configuration changes
if command -v systemctl >/dev/null 2>&1; then
    # Identify GlassFish service name if it exists
    GF_SERVICE=$(systemctl list-units --type=service --state=running | grep -i "glassfish" | awk '{print $1}' | head -n 1)
    if [ -n "$GF_SERVICE" ]; then
        systemctl restart "$GF_SERVICE" 2>/dev/null || true
    fi
fi
```