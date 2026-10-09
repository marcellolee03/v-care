```bash
#!/bin/bash
# Mitigate Apache ActiveMQ Web Console Default Credentials Vulnerability (CVE: nan)
# This script identifies and replaces default "admin:admin" and "user:user"
# credentials in ActiveMQ's users.properties file with strong, randomly generated passwords.
# It is designed to be minimalist, surgical, and idempotent.

set -euo pipefail

# --- Configuration ---
ACTIVEMQ_USERS_FILE="" # Path to the users.properties file, to be determined dynamically
DEFAULT_USERS=("admin" "user")
DEFAULT_PASSWORDS=("admin" "user") # Corresponds to DEFAULT_USERS

# --- Helper Functions ---

# Function to generate a secure random password of 16 alphanumeric characters and underscore.
# Using /dev/urandom for cryptographically secure random numbers.
generate_password() {
    head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 16
}

# Function to locate the ActiveMQ users.properties file.
# Checks common installation paths.
find_activemq_users_file() {
    local common_paths=(
        "/var/lib/activemq/conf/users.properties" # Common for Debian package installs
        "/etc/activemq/users.properties"         # Less common for credentials, more for global config
        "/opt/activemq/conf/users.properties"    # Common for manual installs
    )
    for path in "${common_paths[@]}"; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    return 1 # File not found in any of the common paths
}

# --- Main Logic ---

# 1. Verify script is run as root.
if [[ $(id -u) -ne 0 ]]; then
    echo "Error: This script must be run as root to modify system configuration." >&2
    exit 1
fi

# 2. Locate the ActiveMQ users.properties file.
ACTIVEMQ_USERS_FILE=$(find_activemq_users_file)
if [[ -z "$ACTIVEMQ_USERS_FILE" ]]; then
    echo "Error: Could not find ActiveMQ users.properties file in common locations." >&2
    exit 1
fi

# 3. Ensure the identified file is writable by root.
if [[ ! -w "$ACTIVEMQ_USERS_FILE" ]]; then
    echo "Error: ActiveMQ users.properties file is not writable: $ACTIVEMQ_USERS_FILE" >&2
    exit 1
fi

# 4. Create a backup of the original file before any modifications.
cp "$ACTIVEMQ_USERS_FILE" "${ACTIVEMQ_USERS_FILE}.bak" || {
    echo "Error: Failed to create backup of $ACTIVEMQ_USERS_FILE" >&2
    exit 1
}

changes_made=0 # Flag to track if any changes were applied

# 5. Iterate through default users and change their passwords if they are still using defaults.
for i in "${!DEFAULT_USERS[@]}"; do
    user="${DEFAULT_USERS[$i]}"
    default_password="${DEFAULT_PASSWORDS[$i]}"

    # Check if the exact default password line exists for the current user.
    if grep -q "^${user}=${default_password}$" "$ACTIVEMQ_USERS_FILE"; then
        new_password=$(generate_password)

        # Use sed to replace the specific default line.
        # This is surgical: only replaces if the exact default line is found.
        # This is idempotent: if the line doesn't match the default, no change occurs.
        sed -i "s/^${user}=${default_password}$/${user}=${new_password}/" "$ACTIVEMQ_USERS_FILE" || {
            echo "Error: Failed to update password for user '$user' in $ACTIVEMQ_USERS_FILE." >&2
            # Attempt to revert backup if sed fails
            mv "${ACTIVEMQ_USERS_FILE}.bak" "$ACTIVEMQ_USERS_FILE" 2>/dev/null || true
            exit 1
        }
        changes_made=1 # Mark that a change has occurred
    fi
done

# 6. If changes were made, restart the ActiveMQ service to apply them.
if [[ "$changes_made" -eq 1 ]]; then
    if systemctl is-active --quiet activemq.service; then
        systemctl restart activemq.service || {
            echo "Error: Failed to restart activemq.service. Please restart manually." >&2
            # Attempt to revert backup if service restart fails
            mv "${ACTIVEMQ_USERS_FILE}.bak" "$ACTIVEMQ_USERS_FILE" 2>/dev/null || true
            exit 1
        }
    elif service activemq status >/dev/null 2>&1; then # Fallback for SysVinit if systemctl not available/primary
        service activemq restart || {
            echo "Error: Failed to restart activemq service (sysvinit). Please restart manually." >&2
            # Attempt to revert backup if service restart fails
            mv "${ACTIVEMQ_USERS_FILE}.bak" "$ACTIVEMQ_USERS_FILE" 2>/dev/null || true
            exit 1
        }
    else
        echo "Warning: ActiveMQ service not found or not managed by systemctl/sysvinit. Please restart ActiveMQ manually to apply credential changes." >&2
        # No exit 1 here, as files were changed successfully, only restart is an issue.
    fi
else
    # If no changes were made (i.e., default credentials were not found), remove the backup.
    # This maintains idempotency by not leaving unnecessary artifacts.
    rm -f "${ACTIVEMQ_USERS_FILE}.bak"
fi

exit 0
```