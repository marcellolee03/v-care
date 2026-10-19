```bash
#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

MYSQL_CONF="/etc/mysql/mysql.conf.d/mysqld.cnf"
if [ ! -f "$MYSQL_CONF" ]; then
    MYSQL_CONF="/etc/mysql/my.cnf"
fi

if [ -f "$MYSQL_CONF" ]; then
    if ! grep -q "^bind-address\s*=\s*127.0.0.1" "$MYSQL_CONF"; then
        sed -i '/^\[mysqld\]/a bind-address = 127.0.0.1' "$MYSQL_CONF"
    fi
fi

if command -v mysql >/dev/null 2>&1; then
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$(openssl rand -base64 32)'; FLUSH PRIVILEGES;" 2>/dev/null || true
fi

systemctl restart mysql 2>/dev/null || service mysql restart 2>/dev/null || true
```