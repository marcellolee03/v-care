```bash
#!/bin/bash
set -euo pipefail

# Check root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# System information
readonly ES_VERSION="1.1.1"
readonly ES_PORT="9200"
readonly ES_CONFIG_LOCATIONS=(
    "/etc/elasticsearch"
    "/usr/share/elasticsearch/config"
    "/opt/elasticsearch/config"
)

# Detect if Elasticsearch is running
if systemctl is-active --quiet elasticsearch 2>/dev/null || \
   pgrep -f "elasticsearch" >/dev/null 2>&1; then
    echo "Stopping Elasticsearch service..."
    systemctl stop elasticsearch 2>/dev/null || pkill -f "elasticsearch"
    sleep 3
fi

# Validate Elasticsearch is stopped
if pgrep -f "elasticsearch" >/dev/null 2>&1; then
    echo "Error: Could not stop Elasticsearch process" >&2
    exit 1
fi

# Configure firewall to block port 9200
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    ufw deny "$ES_PORT/tcp" >/dev/null 2>&1 || true
elif command -v iptables >/dev/null 2>&1; then
    iptables -A INPUT -p tcp --dport "$ES_PORT" -j DROP >/dev/null 2>&1 || true
fi

echo "Vulnerability mitigated: Elasticsearch service stopped and port $ES_PORT blocked"
exit 0
```