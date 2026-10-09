```bash
#!/bin/bash
set -euo pipefail

# Constants
ES_SERVICE_NAME="elasticsearch"

# --- Security Checks ---
# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# --- Mitigation Logic ---
# The vulnerability context indicates Elasticsearch version 1.1.1 is installed and vulnerable.
# Direct in-place upgrade from 1.x to 6.x via a simple script is not feasible due to
# significant breaking changes and complex data migration requirements.
# Therefore, the most surgical and minimalist mitigation for the immediate DoS risk,
# without installing new packages or performing complex application-specific upgrades,
# is to stop and disable the vulnerable Elasticsearch service.
# This removes the attack surface for CVE-2021-22144.
# Manual intervention will be required by an administrator for a proper upgrade
# or replacement of the Elasticsearch instance.

# Check if the Elasticsearch service is currently active
if systemctl is-active -q "${ES_SERVICE_NAME}"; then
    # Service is active, stop it to mitigate the DoS vulnerability.
    systemctl stop "${ES_SERVICE_NAME}" &>/dev/null || {
        echo "Error: Failed to stop Elasticsearch service." >&2
        exit 1
    }
fi

# Check if the Elasticsearch service is enabled to start on boot
if systemctl is-enabled -q "${ES_SERVICE_NAME}"; then
    # Service is enabled, disable it from starting automatically on boot.
    systemctl disable "${ES_SERVICE_NAME}" &>/dev/null || {
        echo "Error: Failed to disable Elasticsearch service from autostart." >&2
        exit 1
    }
fi

# The script is designed to be silent on success. Errors are reported to stderr.
# If the service was already stopped and disabled, the checks will pass silently,
# ensuring idempotence.
```