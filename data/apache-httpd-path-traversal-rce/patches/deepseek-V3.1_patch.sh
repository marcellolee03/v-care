```bash
#!/bin/bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" >&2
    exit 1
fi

APACHE_CONF_DIR="/etc/apache2"
APACHE_CONF_FILE="${APACHE_CONF_DIR}/apache2.conf"

if [[ ! -d "$APACHE_CONF_DIR" ]]; then
    echo "Apache configuration directory not found: $APACHE_CONF_DIR" >&2
    exit 1
fi

if [[ ! -f "$APACHE_CONF_FILE" ]]; then
    echo "Apache configuration file not found: $APACHE_CONF_FILE" >&2
    exit 1
fi

CGID_MODULE_FILE="${APACHE_CONF_DIR}/mods-enabled/cgid.load"
if [[ -f "$CGID_MODULE_FILE" ]]; then
    a2dismod -q cgid
fi

CGI_MODULE_FILE="${APACHE_CONF_DIR}/mods-enabled/cgi.load"
if [[ -f "$CGI_MODULE_FILE" ]]; then
    a2dismod -q cgi
fi

systemctl reload apache2 >/dev/null 2>&1
```