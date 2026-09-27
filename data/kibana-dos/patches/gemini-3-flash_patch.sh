```bash
#!/bin/bash

# CVE-2021-22139 (ESA-2021-10) Mitigation Script
# Task: Mitigate Denial of Service vulnerability in Kibana by upgrading to the fixed version.
# Environment: CentOS 7 (Core)

set -euo pipefail

# 1. Security: Verify root privileges
if [[ "${EUID}" -ne 0 ]]; then
    echo "Error: This script must be run with root privileges." >&2
    exit 1
fi

# 2. Surgical Logic: Identify if Kibana is managed via RPM and check version
if rpm -q kibana >/dev/null 2>&1; then
    CURRENT_VERSION=$(rpm -q --queryformat '%{VERSION}' kibana)
    FIXED_VERSION="7.12.1"

    # Idempotent check: Use version comparison to determine if upgrade is needed
    # (6.5.4 < 7.12.1)
    IS_VULNERABLE=$(printf '%s\n%s' "$CURRENT_VERSION" "$FIXED_VERSION" | sort -V | head -n1)

    if [[ "$CURRENT_VERSION" != "$FIXED_VERSION" && "$IS_VULNERABLE" == "$CURRENT_VERSION" ]]; then
        
        # 3. Apply exact fix: Upgrade to the specific fixed version
        # Uses yum (native to CentOS 7). Redirects stdout to /dev/null to remain silent.
        yum install -y -q "kibana-${FIXED_VERSION}" >/dev/null || {
            echo "Error: Failed to upgrade Kibana to ${FIXED_VERSION}. Check repository configuration." >&2
            exit 1
        }

        # 4. Restart service to apply changes if systemd is present
        if systemctl is-active --quiet kibana; then
            systemctl restart kibana >/dev/null 2>&1 || true
        fi
    fi
fi

exit 0
```