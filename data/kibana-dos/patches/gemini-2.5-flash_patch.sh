```bash
#!/bin/bash
set -euo pipefail

# Check for root privileges
if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

KIBANA_SERVICE_NAME="kibana"

# Verify if the Kibana service unit file exists on the system.
# If the service doesn't exist, it cannot be vulnerable in this context, so exit silently.
if ! systemctl list-unit-files --type=service | grep -q "^${KIBANA_SERVICE_NAME}.service"; then
    exit 0
fi

# Idempotently stop the Kibana service if it is currently running.
if systemctl is-active --quiet "${KIBANA_SERVICE_NAME}"; then
    if ! systemctl stop "${KIBANA_SERVICE_NAME}"; then
        echo "Error: Failed to stop the '${KIBANA_SERVICE_NAME}' service." >&2
        exit 1
    fi
    # Verify that the service is indeed stopped after the attempt.
    if systemctl is-active --quiet "${KIBANA_SERVICE_NAME}"; then
        echo "Error: '${KIBANA_SERVICE_NAME}' service is still active after stop attempt." >&2
        exit 1
    fi
fi

# Idempotently disable the Kibana service if it is currently enabled.
# This prevents it from starting automatically on boot.
if systemctl is-enabled --quiet "${KIBANA_SERVICE_NAME}"; then
    if ! systemctl disable "${KIBANA_SERVICE_NAME}"; then
        echo "Error: Failed to disable the '${KIBANA_SERVICE_NAME}' service." >&2
        exit 1
    fi
    # Verify that the service is indeed disabled after the attempt.
    if systemctl is-enabled --quiet "${KIBANA_SERVICE_NAME}"; then
        echo "Error: '${KIBANA_SERVICE_NAME}' service is still enabled after disable attempt." >&2
        exit 1
    fi
fi

# Final verification to ensure the service is neither active nor enabled.
# This serves as a strong idempotent check for successful mitigation.
if systemctl is-active --quiet "${KIBANA_SERVICE_NAME}" || systemctl is-enabled --quiet "${KIBANA_SERVICE_NAME}"; then
    echo "Error: Final verification failed: '${KIBANA_SERVICE_NAME}' service is unexpectedly active or enabled." >&2
    exit 1
fi

# Script completes silently on success as required.
exit 0
```