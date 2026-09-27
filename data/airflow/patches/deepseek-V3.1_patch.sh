```bash
#!/bin/bash
set -euo pipefail

readonly VULNERABLE_FILE="/static/js/jquery-1.7.2.min.js"
readonly TARGET_VERSION="1.9.0"
readonly JQUERY_URL="https://code.jquery.com/jquery-${TARGET_VERSION}.min.js"

if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

if [[ ! -f "${VULNERABLE_FILE}" ]]; then
    echo "Error: Vulnerable file not found at ${VULNERABLE_FILE}" >&2
    exit 1
fi

if curl --silent --fail --head "${JQUERY_URL}" >/dev/null; then
    curl --silent --fail --output "${VULNERABLE_FILE}" "${JQUERY_URL}"
else
    echo "Error: Failed to download jQuery ${TARGET_VERSION}" >&2
    exit 1
fi
```