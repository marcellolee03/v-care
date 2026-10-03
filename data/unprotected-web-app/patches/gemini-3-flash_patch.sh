```bash
#!/bin/bash
set -euo pipefail

# Role: Senior System Security Engineer
# Purpose: Mitigate unprotected Jira installer by restricting web access to localhost
# Target: Atlassian Jira on Ubuntu 18.04

# Verify root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Root privileges required." >&2
    exit 1
fi

# 1. Identify the Jira installation directory
# First, attempt to extract it from the running process environment variable
# Second, fall back to the common default installation path
JIRA_BASE=$(ps -ef | sed -n 's/.*-Djira.install=\([^ ]*\).*/\1/p' | head -n 1)
JIRA_BASE="${JIRA_BASE:-/opt/atlassian/jira}"
CONF_FILE="$JIRA_BASE/conf/server.xml"

# 2. Apply surgical mitigation at the configuration level
# This restricts the HTTP Connector to bind only to the loopback interface (127.0.0.1),
# effectively preventing public access to the installer/setup pages.
if [ -f "$CONF_FILE" ]; then
    # Idempotency check: Ensure port 8080 is found and no address attribute is already defined
    if grep -q 'port="8080"' "$CONF_FILE" && ! grep -q 'port="8080"[^>]*address=' "$CONF_FILE"; then
        
        # Insert address="127.0.0.1" into the Connector element for port 8080
        sed -i '/port="8080"/s/port="8080"/port="8080" address="127.0.0.1"/' "$CONF_FILE"
        
        # 3. Restart the service to apply changes
        # Checks common service names for Atlassian Jira
        for service_name in jira atlassian-jira; do
            if systemctl is-active --quiet "$service_name"; then
                systemctl restart "$service_name" > /dev/null 2>&1 || echo "Warning: Failed to restart $service_name" >&2
                break
            fi
        done
    fi
fi
```