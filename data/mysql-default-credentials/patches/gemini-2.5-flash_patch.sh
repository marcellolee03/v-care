```bash
#!/bin/bash
set -euo pipefail

# --- Pre-checks ---

# Verify that the script is run as root.
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# Verify that the 'mysql' client is available.
if ! command -v mysql &> /dev/null; then
    echo "Error: MySQL client 'mysql' not found. Please ensure it is installed and in PATH." >&2
    exit 1
fi

# --- Vulnerability Details ---
WEAK_PASSWORD="123456"
TARGET_USER="root"
MYSQL_HOST="127.0.0.1" # Target local MySQL server over TCP/IP (port 3306)

# --- Idempotency Check & Mitigation ---

# Attempt to log in to the local MySQL server with the known weak credentials.
# This check determines if the vulnerability is currently present.
# Output is suppressed to maintain silence on success.
if mysql -h "${MYSQL_HOST}" -u "${TARGET_USER}" -p"${WEAK_PASSWORD}" -e "SELECT 1;" &> /dev/null; then
    # Login successful, indicating the vulnerability exists. Proceed with mitigation.

    # Generate a new strong, random password.
    # The new password is 32 characters long, containing uppercase, lowercase, numbers, and underscore.
    NEW_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 32)
    if [ -z "${NEW_PASSWORD}" ]; then
        echo "Error: Failed to generate a new strong password." >&2
        exit 1
    fi

    PASSWORD_CHANGE_SUCCESS=0 # Flag to track if any password was successfully changed

    # Change password for 'root'@'localhost'.
    # Execute ALTER USER using the current weak credentials.
    if mysql -h "${MYSQL_HOST}" -u "${TARGET_USER}" -p"${WEAK_PASSWORD}" -e "ALTER USER '${TARGET_USER}'@'localhost' IDENTIFIED BY '${NEW_PASSWORD}';" &> /dev/null; then
        PASSWORD_CHANGE_SUCCESS=1
    else
        echo "Warning: Failed to change password for '${TARGET_USER}'@'localhost'. Manual intervention might be required." >&2
    fi

    # Check if 'root'@'%' exists and change its password if the weak credentials work for it.
    # This addresses potential remote access with weak credentials.
    # First, try to list the user to check its existence, then attempt password change.
    if mysql -h "${MYSQL_HOST}" -u "${TARGET_USER}" -p"${WEAK_PASSWORD}" -e "SELECT User FROM mysql.user WHERE User='${TARGET_USER}' AND Host='%';" &> /dev/null; then
        if mysql -h "${MYSQL_HOST}" -u "${TARGET_USER}" -p"${WEAK_PASSWORD}" -e "ALTER USER '${TARGET_USER}'@'%' IDENTIFIED BY '${NEW_PASSWORD}';" &> /dev/null; then
            PASSWORD_CHANGE_SUCCESS=1
        else
            echo "Warning: Failed to change password for '${TARGET_USER}'@'%'. Manual intervention might be required." >&2
        fi
    fi

    # Flush privileges to ensure all password changes take effect immediately.
    # This must be done using the *current* (weak) credentials from the active session.
    if ! mysql -h "${MYSQL_HOST}" -u "${TARGET_USER}" -p"${WEAK_PASSWORD}" -e "FLUSH PRIVILEGES;" &> /dev/null; then
        echo "Error: Failed to flush MySQL privileges after password change attempts." >&2
        exit 1
    fi

    # Report an error if the weak credentials were found but no password changes were applied.
    if [ "${PASSWORD_CHANGE_SUCCESS}" -eq 0 ]; then
        echo "Error: Vulnerable credentials found, but no password changes were successfully applied. Check MySQL logs for details." >&2
        exit 1
    fi

    # If successful, the script completes silently.
else
    # Login with weak credentials failed, implying the vulnerability is not present or already mitigated.
    # Exit silently as per idempotency requirement.
    exit 0
fi

exit 0 # Script finished successfully (mitigation applied)
```