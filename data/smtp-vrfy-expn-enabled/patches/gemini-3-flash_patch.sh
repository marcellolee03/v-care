```bash
#!/bin/bash
set -euo pipefail

# Ensure the script is running with root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# Mitigation for Postfix (standard MTA for Debian/Ubuntu-based systems like Pop!_OS)
if command -v postconf >/dev/null 2>&1 && [ -f /etc/postfix/main.cf ]; then
    # Check if disable_vrfy_command is already set to yes to maintain idempotency
    CURRENT_VAL=$(postconf -h disable_vrfy_command 2>/dev/null || echo "no")
    
    if [ "$CURRENT_VAL" != "yes" ]; then
        # Disable VRFY and EXPN (Postfix ignores EXPN by default, but VRFY needs explicit disabling)
        postconf -e "disable_vrfy_command = yes"
        
        # Reload configuration silently
        if command -v systemctl >/dev/null 2>&1; then
            systemctl reload postfix >/dev/null 2>&1 || true
        else
            service postfix reload >/dev/null 2>&1 || true
        fi
    fi
fi

# Mitigation for Exim4 (alternative MTA)
if [ -d /etc/exim4 ] && command -v exim4 >/dev/null 2>&1; then
    CONF_FILE="/etc/exim4/conf.d/main/02_exim4-config_options"
    # For monolithic config
    [ -f /etc/exim4/exim4.conf.template ] && CONF_FILE="/etc/exim4/exim4.conf.template"
    
    if [ -f "$CONF_FILE" ]; then
        if ! grep -q "smtp_verify = false" "$CONF_FILE"; then
            # Append options if not present
            echo "smtp_verify = false" >> "$CONF_FILE"
            echo "acl_smtp_vrfy = deny" >> "$CONF_FILE"
            echo "acl_smtp_expn = deny" >> "$CONF_FILE"
            
            if command -v update-exim4.conf >/dev/null 2>&1; then
                update-exim4.conf
                systemctl reload exim4 >/dev/null 2>&1 || true
            fi
        fi
    fi
fi
```