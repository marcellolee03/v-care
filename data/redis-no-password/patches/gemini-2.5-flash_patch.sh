```bash
#!/bin/bash

# --- Security and Error Handling ---
# Exit immediately if a command exits with a non-zero status.
# Exit if an unset variable is used.
# The return value of a pipeline is the status of the last command to exit with a non-zero status,
# or zero if all commands in the pipeline exit successfully.
set -euo pipefail
# Set IFS to newline and tab to prevent word splitting issues with spaces in filenames.
IFS=$'\n\t'

# --- Global Variables ---
REDIS_CONF_FILE="/etc/redis/redis.conf"
REDIS_SERVICE_NAME="redis-server"

# --- Functions ---

# Function to check for root privileges.
# Exits with an error if the script is not run as root.
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "Error: This script must be run as root." >&2
        exit 1
    fi
}

# Function to generate a strong random password.
# Outputs a 32-character alphanumeric string.
generate_password() {
    head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32
}

# --- Main Logic ---
check_root

# Verify that the Redis configuration file exists.
if [[ ! -f "$REDIS_CONF_FILE" ]]; then
    echo "Error: Redis configuration file not found at $REDIS_CONF_FILE." >&2
    exit 1
fi

# Flag to track if the configuration file was modified.
CONFIG_MODIFIED=0

# --- Handle 'requirepass' directive ---
# Check if 'requirepass' is already uncommented and has a value.
# The -P flag enables Perl-compatible regular expressions for better pattern matching.
if ! grep -qP '^\s*requirepass\s+\S+' "$REDIS_CONF_FILE"; then
    # 'requirepass' is either commented out or missing.
    NEW_PASSWORD=$(generate_password)

    # Check if 'requirepass' is commented out.
    if grep -qP '^\s*#\s*requirepass\s+' "$REDIS_CONF_FILE"; then
        # 'requirepass' is commented, uncomment it and set the new password.
        # -i for in-place editing, -E for extended regex.
        sed -i -E "s/^(#\s*)?requirepass\s+.*/requirepass ${NEW_PASSWORD}/" "$REDIS_CONF_FILE"
        CONFIG_MODIFIED=1
    else
        # 'requirepass' is missing, append it to the end of the file.
        echo "requirepass ${NEW_PASSWORD}" >> "$REDIS_CONF_FILE"
        CONFIG_MODIFIED=1
    fi
fi

# --- Handle 'protected-mode' directive ---
# Ensure 'protected-mode yes' is set. This helps prevent direct access from non-loopback
# interfaces if no 'bind' directive is specified, even with 'requirepass' set.
# Check if 'protected-mode yes' is already active.
if ! grep -qP '^\s*protected-mode\s+yes' "$REDIS_CONF_FILE"; then
    # 'protected-mode' exists (commented or set to 'no'/other value), or is missing.
    # Check if 'protected-mode' line exists (commented or uncommented).
    if grep -qP '^\s*#?\s*protected-mode\s+' "$REDIS_CONF_FILE"; then
        # 'protected-mode' line exists, ensure it's set to 'yes'.
        sed -i -E "s/^(#\s*)?protected-mode\s+.*/protected-mode yes/" "$REDIS_CONF_FILE"
        CONFIG_MODIFIED=1
    else
        # 'protected-mode' is missing, append it to the end of the file.
        echo "protected-mode yes" >> "$REDIS_CONF_FILE"
        CONFIG_MODIFIED=1
    fi
fi

# --- Apply changes if the configuration file was modified ---
if [[ "$CONFIG_MODIFIED" -eq 1 ]]; then
    # Set appropriate permissions for the configuration file (read/write for owner, read-only for group).
    chmod 640 "$REDIS_CONF_FILE" || { echo "Error: Failed to set permissions on $REDIS_CONF_FILE." >&2; exit 1; }

    # Attempt to set the owner to 'redis:redis', fallback to 'redis:root', then warn if still unsuccessful.
    # Redirect stderr to /dev/null for chown commands to suppress "No such user/group" errors.
    if ! chown redis:redis "$REDIS_CONF_FILE" 2>/dev/null; then
        if ! chown redis:root "$REDIS_CONF_FILE" 2>/dev/null; then
            echo "Warning: Failed to set owner on $REDIS_CONF_FILE. File owned by root:root. Proceeding with restart." >&2
        fi
    fi

    # Restart Redis service to apply the configuration changes.
    # Use systemctl for service management, common on Debian 9.
    # Check if the service is active before attempting to restart. If not, try to start it.
    if ! systemctl is-active --quiet "$REDIS_SERVICE_NAME"; then
        if ! systemctl start "$REDIS_SERVICE_NAME"; then
            echo "Error: Failed to start Redis service after configuration changes." >&2
            exit 1
        fi
    else
        if ! systemctl restart "$REDIS_SERVICE_NAME"; then
            echo "Error: Failed to restart Redis service after configuration changes." >&2
            exit 1
        fi
    fi
fi

# The script is silent on success as per requirements.
```