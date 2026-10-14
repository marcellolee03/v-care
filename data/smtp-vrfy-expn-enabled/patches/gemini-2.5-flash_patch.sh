```bash
#!/bin/bash
# Minimalist, surgical, and idempotent BASH script to mitigate mail server VRFY/EXPN vulnerability.

# --- Security and Error Handling ---
set -euo pipefail

# Ensure the script is run as root
if [[ "${EUID}" -ne 0 ]]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# --- Assumptions ---
# This script assumes Postfix is the Mail Transfer Agent (MTA) in use.
# The mitigation applies by modifying Postfix's main.cf configuration.
# If a different MTA (e.g., Sendmail, Exim) is installed, this script will not be effective.

# --- Configuration Variables ---
POSTFIX_MAIN_CF="/etc/postfix/main.cf"
DATE_SUFFIX=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${POSTFIX_MAIN_CF}.${DATE_SUFFIX}.bak"

# --- Vulnerability Mitigation Logic ---

# 1. Check for Postfix configuration file existence
if [[ ! -f "${POSTFIX_MAIN_CF}" ]]; then
    echo "Error: Postfix main configuration file not found at ${POSTFIX_MAIN_CF}." >&2
    echo "This script assumes Postfix is the MTA. If a different MTA is used, manual configuration is required." >&2
    exit 1
fi

# 2. Create a backup of the original configuration file
if ! cp "${POSTFIX_MAIN_CF}" "${BACKUP_FILE}"; then
    echo "Error: Failed to create a backup of ${POSTFIX_MAIN_CF} to ${BACKUP_FILE}." >&2
    exit 1
fi

# 3. Disable VRFY command
# This block first removes any existing 'disable_vrfy_command' lines (including commented ones),
# then appends the desired configuration. This ensures idempotency and correct value.
if grep -qE "^[[:space:]]*disable_vrfy_command[[:space:]]*=" "${POSTFIX_MAIN_CF}"; then
    sed -i -E "/^[[:space:]]*disable_vrfy_command[[:space:]]*=/d" "${POSTFIX_MAIN_CF}"
fi
echo "disable_vrfy_command = yes" >> "${POSTFIX_MAIN_CF}"

# 4. Disable EXPN command
# This block first removes any existing 'disable_expn_command' lines (including commented ones),
# then appends the desired configuration. This ensures idempotency and correct value.
if grep -qE "^[[:space:]]*disable_expn_command[[:space:]]*=" "${POSTFIX_MAIN_CF}"; then
    sed -i -E "/^[[:space:]]*disable_expn_command[[:space:]]*=/d" "${POSTFIX_MAIN_CF}"
fi
echo "disable_expn_command = yes" >> "${POSTFIX_MAIN_CF}"

# 5. Reload Postfix to apply changes
# Check if Postfix service is active before attempting to reload.
if systemctl is-active --quiet postfix; then
    if ! systemctl reload postfix; then
        echo "Error: Failed to reload Postfix service. Please check Postfix logs for details." >&2
        exit 1
    fi
else
    echo "Warning: Postfix service does not appear to be active or installed. Configuration has been updated, but the service was not reloaded." >&2
fi

exit 0
```