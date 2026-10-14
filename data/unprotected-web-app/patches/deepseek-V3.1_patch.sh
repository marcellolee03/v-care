```bash
#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

readonly JIRA_CONFIG="/opt/atlassian/jira/conf/server.xml"
readonly CONNECTOR_CONFIG='<Connector port="8080"'

if [ ! -f "$JIRA_CONFIG" ]; then
    echo "Error: Jira configuration file not found at $JIRA_CONFIG" >&2
    exit 1
fi

if ! grep -q "$CONNECTOR_CONFIG" "$JIRA_CONFIG"; then
    echo "Error: Connector configuration not found in $JIRA_CONFIG" >&2
    exit 1
fi

sed -i '/<Connector port="8080"/s/\(address=\)"[^"]*"/\1"127.0.0.1"/' "$JIRA_CONFIG"

if ! systemctl is-active --quiet jira; then
    echo "Error: Jira service is not running" >&2
    exit 1
fi

systemctl restart jira
```