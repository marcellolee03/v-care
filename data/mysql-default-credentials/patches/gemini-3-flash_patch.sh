```bash
#!/bin/bash
# Senior System Security Engineer - MySQL/MariaDB Hardening Script
# Target: Mitigate default root credentials (CVE-2001-0645, etc.)

set -euo pipefail

# Verify root privileges
if [ "$(id -u)" -ne 0 ]; then
    exit 1
fi

DB_USER="root"
OLD_PASS="123456"

# Check if the vulnerability exists (Idempotency)
if mysql -u "$DB_USER" -p"$OLD_PASS" -e "exit" >/dev/null 2>&1; then
    # Generate a cryptographically secure 32-character password
    NEW_PASS=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 32)

    # Retrieve all hosts associated with the root user
    HOSTS=$(mysql -u "$DB_USER" -p"$OLD_PASS" -N -s -e "SELECT Host FROM mysql.user WHERE User='$DB_USER'")

    for host in $HOSTS; do
        # Attempt mitigation using ALTER USER (MySQL 5.7+) or SET PASSWORD (MariaDB/Legacy)
        mysql -u "$DB_USER" -p"$OLD_PASS" -e "ALTER USER '$DB_USER'@'$host' IDENTIFIED BY '$NEW_PASS';" >/dev/null 2>&1 || \
        mysql -u "$DB_USER" -p"$OLD_PASS" -e "SET PASSWORD FOR '$DB_USER'@'$host' = PASSWORD('$NEW_PASS');" >/dev/null 2>&1
    done

    # Finalize privileges
    mysql -u "$DB_USER" -p"$NEW_PASS" -e "FLUSH PRIVILEGES;" >/dev/null 2>&1

    # Securely store the new credential for administrative recovery
    printf "%s\n" "$NEW_PASS" > /root/.mysql_root_secured
    chmod 400 /root/.mysql_root_secured
fi
```