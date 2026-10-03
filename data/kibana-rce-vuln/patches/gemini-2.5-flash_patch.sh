```bash
#!/bin/bash

# Enable strict error handling for robustness
set -euo pipefail

# --- Pre-checks ---

# Verify root privileges
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: This script must be run as root." >&2
  exit 1
fi

# --- Mitigation Steps ---

# Store initial Kibana service status to ensure idempotency when restarting.
# We only want to start it if it was running before the update.
kibana_was_running=false
if systemctl is-active --quiet kibana.service; then
  kibana_was_running=true
fi

# 1. Stop Kibana service if it's currently running.
if "$kibana_was_running"; then
  if ! systemctl stop kibana.service; then
    echo "Error: Failed to stop Kibana service. Please check its status and logs." >&2
    exit 1
  fi
fi

# 2. Update Kibana package.
# 'yum update -y kibana' will only update if a newer version is available.
# This operation is idempotent: if Kibana is already at the latest version,
# yum will report "No packages marked for update" and exit successfully.
if ! yum update -y kibana; then
  echo "Error: Failed to update Kibana. Please check your yum repositories and network connection." >&2
  # Attempt to restart Kibana if it was running before the failed update, as a best effort.
  if "$kibana_was_running"; then
    systemctl start kibana.service 2>/dev/null || true # Suppress potential error if starting fails again.
  fi
  exit 1
fi

# 3. Start Kibana service if it was running before the update.
if "$kibana_was_running"; then
  if ! systemctl start kibana.service; then
    echo "Error: Failed to start Kibana service. Please check its logs." >&2
    exit 1
  fi
fi

# Script exits silently on success.
exit 0
```