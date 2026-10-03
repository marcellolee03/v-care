```bash
#!/bin/bash
set -euo pipefail

# Ensure the script is running with root privileges
if [ "$EUID" -ne 0 ]; then
    exit 1
fi

# Locate the Apache ActiveMQ Jetty authentication configuration file.
# Common installation paths are searched to identify the realm properties file.
CONF_FILE=$(find /opt /etc /usr/share /var/lib -name "jetty-realm.properties" 2>/dev/null | head -n 1 || true)

# If the configuration file exists, mitigate the default credential vulnerability
if [ -n "$CONF_FILE" ] && [ -f "$CONF_FILE" ]; then
    # Idempotently comment out default 'admin' and 'user' accounts if they still use default passwords.
    # The regex ensures we only target the specific default combinations reported.
    # \b ensures word boundary matching for the password strings.
    sed -i 's/^admin:[[:space:]]*admin\b/#&/' "$CONF_FILE"
    sed -i 's/^user:[[:space:]]*user\b/#&/' "$CONF_FILE"
fi
```