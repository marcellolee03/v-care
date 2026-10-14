```bash
#!/bin/bash
set -euo pipefail

# Verify root privileges
if [[ $EUID -ne 0 ]]; then
    exit 1
fi

# Target: Grafana (the standard application associated with port 3000 and the specified login path)
# Path: /etc/grafana/grafana.ini (default Debian location)
CONF_FILE="/etc/grafana/grafana.ini"

if [[ -f "$CONF_FILE" ]]; then
    # 1. Enforce HTTPS protocol
    # Uses sed to uncomment or update the 'protocol' line to 'https'
    sed -i 's/^[; ]*protocol =.*/protocol = https/' "$CONF_FILE"

    # 2. Enforce Secure Cookies
    # Ensures that the 'cookie_secure' flag is set to true to prevent transmission over HTTP
    sed -i 's/^[; ]*cookie_secure =.*/cookie_secure = true/' "$CONF_FILE"

    # 3. Apply changes via systemd if the service is present
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet grafana-server; then
            systemctl restart grafana-server >/dev/null 2>&1 || true
        fi
    fi
fi

# Alternative Target: Gitea (another common application on port 3000)
GITEA_CONF="/etc/gitea/app.ini"
if [[ -f "$GITEA_CONF" ]]; then
    # Enforce PROTOCOL = https
    sed -i 's/^PROTOCOL *=.*/PROTOCOL = https/' "$GITEA_CONF"
    
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet gitea; then
            systemctl restart gitea >/dev/null 2>&1 || true
        fi
    fi
fi

exit 0
```