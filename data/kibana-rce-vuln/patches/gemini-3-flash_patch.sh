```bash
#!/bin/bash
set -euo pipefail

# Mitigation for CVE-2019-7609: Disabling Timelion in Kibana
# Affected: Kibana < 5.6.15, 6.x.x < 6.6.1

[[ $EUID -ne 0 ]] && exit 1

KIBANA_CONF="/etc/kibana/kibana.yml"

# Ensure the configuration file exists
[[ -f "$KIBANA_CONF" ]] || exit 1

# Check if the mitigation is already applied
if ! grep -qE "^timelion.enabled: false" "$KIBANA_CONF"; then
    if grep -q "^timelion.enabled:" "$KIBANA_CONF"; then
        # Update existing entry
        sed -i 's/^timelion.enabled:.*/timelion.enabled: false/' "$KIBANA_CONF"
    else
        # Append entry if not present
        echo "timelion.enabled: false" >> "$KIBANA_CONF"
    fi

    # Restart service to apply changes if it exists and is managed by systemd
    if systemctl list-unit-files | grep -q "kibana.service"; then
        systemctl restart kibana
    fi
fi
```