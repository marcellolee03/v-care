```bash
#!/bin/bash

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Error: Root privileges required" >&2
    exit 1
fi

COOKIE_CONFIG="/etc/default/webapp-cookie-config"
COOKIE_LINE='Set-Cookie: JSESSIONID=;Path=/;HttpOnly'

if [ ! -f "$COOKIE_CONFIG" ]; then
    echo "Error: Configuration file $COOKIE_CONFIG not found" >&2
    exit 1
fi

if grep -q "HttpOnly" "$COOKIE_CONFIG"; then
    exit 0
fi

sed -i '/Set-Cookie: JSESSIONID=.*Path=\//s/$/;HttpOnly/' "$COOKIE_CONFIG"

if ! grep -q "HttpOnly" "$COOKIE_CONFIG"; then
    echo "Error: Failed to add HttpOnly attribute to cookie configuration" >&2
    exit 1
fi
```