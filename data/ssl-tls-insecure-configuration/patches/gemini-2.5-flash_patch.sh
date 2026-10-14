```bash
#!/bin/bash
set -euo pipefail

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

POSTFIX_CONFIG="/etc/postfix/main.cf"
POSTFIX_SERVICE="postfix"

# Check if Postfix configuration file exists
if [ ! -f "$POSTFIX_CONFIG" ]; then
    echo "Error: Postfix configuration file not found at '$POSTFIX_CONFIG'. Cannot apply mitigation for Postfix." >&2
    exit 1
fi

# Flag to track if a service restart is needed
RESTART_REQUIRED=0

# Function to update or add a Postfix parameter
# Arguments: $1 = parameter_name, $2 = desired_value, $3 = config_file
update_postfix_param() {
    local param_name="$1"
    local desired_value="$2"
    local config_file="$3"

    # Escape regex special characters in desired_value for grep matching
    # This ensures that characters like '.' in TLSv1.2 are treated literally.
    local escaped_desired_value=$(echo "$desired_value" | sed -r 's/([.\[\](){}\*+?|^$|\\-])/\\\1/g')

    # Check if the parameter already exists with the desired value (ignoring leading/trailing whitespace and comments)
    if grep -E "^\s*${param_name}\s*=\s*${escaped_desired_value}\s*(#.*)?$" "$config_file" >/dev/null; then
        return 0 # Configuration is already correct, no change needed
    fi

    # Check if the parameter exists with a different value
    if grep -E "^\s*${param_name}\s*=" "$config_file" >/dev/null; then
        # Update the existing parameter line using 'c\' (change line) command
        # This replaces the first occurrence of the parameter definition found.
        sed -i "/^\s*${param_name}\s*=/c\\${param_name} = ${desired_value}" "$config_file"
        RESTART_REQUIRED=1
    else
        # Add the parameter if it does not exist in the file
        echo "${param_name} = ${desired_value}" >> "$config_file"
        RESTART_REQUIRED=1
    fi
}

# --- Apply Postfix TLS protocol configuration ---
# These settings disable TLSv1.0 and TLSv1.1 by explicitly allowing only TLSv1.2 and TLSv1.3.
# smtpd_tls_protocols: For incoming SMTP connections (server-side).
update_postfix_param "smtpd_tls_protocols" "TLSv1.2 TLSv1.3" "$POSTFIX_CONFIG"

# smtp_tls_protocols: For outgoing SMTP connections (client-side, if Postfix acts as a client).
update_postfix_param "smtp_tls_protocols" "TLSv1.2 TLSv1.3" "$POSTFIX_CONFIG"

# smtpd_tls_mandatory_protocols: Enforce mandatory TLS protocols for incoming connections.
update_postfix_param "smtpd_tls_mandatory_protocols" "TLSv1.2 TLSv1.3" "$POSTFIX_CONFIG"

# smtp_tls_mandatory_protocols: Enforce mandatory TLS protocols for outgoing connections.
update_postfix_param "smtp_tls_mandatory_protocols" "TLSv1.2 TLSv1.3" "$POSTFIX_CONFIG"

# Restart Postfix service if any configuration changes were made
if [ "$RESTART_REQUIRED" -eq 1 ]; then
    # Verify systemd is running and the postfix service is recognized before attempting restart
    if systemctl is-system-running --quiet && systemctl list-units --type=service --all | grep -qw "$POSTFIX_SERVICE"; then
        systemctl restart "$POSTFIX_SERVICE" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            : # Silent success: Service restarted
        else
            echo "Error: Failed to restart Postfix service with systemctl. Manual intervention may be required." >&2
            exit 1
        fi
    else
        echo "Warning: Postfix service not found, not managed by systemctl, or systemd not fully running." >&2
        echo "Configuration updated, but the service was not restarted automatically. Manual restart may be required for changes to take effect." >&2
        exit 1 # Indicate a partial failure as the service was not restarted
    fi
fi
```