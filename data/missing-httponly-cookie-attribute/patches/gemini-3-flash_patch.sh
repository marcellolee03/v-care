```bash
#!/bin/bash
set -euo pipefail

# Mitigation Script: Missing HttpOnly Cookie Attribute (JSESSIONID)
# Target Environment: Debian 9, Tomcat/Java Application Servers
# Logic: Enforce useHttpOnly="true" in global and local context configurations.

# Verify root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# Identify Tomcat configuration files responsible for session cookie behavior
# Standard locations for Tomcat 7/8/9 on Debian systems
TARGET_FILES=$(find /etc/tomcat* /var/lib/tomcat* -name "context.xml" 2>/dev/null || true)

for config_file in $TARGET_FILES; do
    if [ -f "$config_file" ]; then
        # Idempotent logic:
        # 1. If useHttpOnly="false" exists, flip it to true.
        # 2. If useHttpOnly attribute is missing from the <Context> tag, add it.
        if grep -q "useHttpOnly=\"false\"" "$config_file"; then
            sed -i 's/useHttpOnly="false"/useHttpOnly="true"/g' "$config_file"
        elif ! grep -q "useHttpOnly" "$config_file"; then
            # Inject useHttpOnly="true" into the opening <Context> tag
            sed -i 's/<Context/<Context useHttpOnly="true"/' "$config_file"
        fi
    fi
done

# Note: For the changes to take effect, the relevant application service 
# (e.g., tomcat8) should be restarted. This script focuses on the configuration fix.
```