```bash
#!/bin/bash
# CVE-2021-22144 Mitigation Script
# Target: Elasticsearch < 6.8.17 or < 7.13.3 (Detected: 1.1.1)
# OS: Debian 9 (stretch)

set -euo pipefail

# Verify root privileges
if [[ "${EUID}" -ne 0 ]]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# Configuration
FIXED_VERSION="6.8.17"
REPO_FILE="/etc/apt/sources.list.d/elastic-6.x.list"
GPG_URL="https://artifacts.elastic.co/GPG-KEY-elasticsearch"
REPO_URL="https://artifacts.elastic.co/packages/6.x/apt"

# Idempotency: Check if elasticsearch is installed and determine version
# Using dpkg-query to extract the version string surgically
INSTALLED_VER=$(dpkg-query -W -f='${Version}' elasticsearch 2>/dev/null | awk -F':|-' '{print $NF}' || true)

# If elasticsearch is not found, or version is already patched, exit silently
if [[ -z "$INSTALLED_VER" ]] || dpkg --compare-versions "$INSTALLED_VER" ge "$FIXED_VERSION"; then
    exit 0
fi

# Mitigation process
{
    # 1. Install prerequisites for secure repository access
    apt-get update -qq
    apt-get install -qq -y apt-transport-https gnupg > /dev/null

    # 2. Import Elastic GPG Key
    wget -qO - "$GPG_URL" | apt-key add - > /dev/null

    # 3. Add the Elastic 6.x repository (contains the fixed 6.8.17 version)
    echo "deb $REPO_URL stable main" > "$REPO_FILE"

    # 4. Update package index and upgrade to the surgical version
    # Force-confold ensures old configurations are kept to maintain idempotency/stability
    apt-get update -qq
    apt-get install -qq -y -o Dpkg::Options::="--force-confold" elasticsearch="$FIXED_VERSION" > /dev/null

    # 5. Reload and restart service if it was previously active
    if systemctl is-active --quiet elasticsearch; then
        systemctl daemon-reload
        systemctl restart elasticsearch
    fi
} > /dev/null 2>&1 || {
    echo "Error: Failed to mitigate CVE-2021-22144. Check network or repository status." >&2
    exit 1
}

exit 0
```