```bash
#!/bin/bash
set -euo pipefail

readonly VULNERABLE_FILE="/themes/default/js/jquery.js"
readonly MIN_VERSION="1.9.0"
readonly CURRENT_VERSION="1.7.1"

# Verify root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Check if vulnerable file exists
if [ ! -f "$VULNERABLE_FILE" ]; then
    echo "Error: Vulnerable file not found at $VULNERABLE_FILE" >&2
    exit 1
fi

# Verify current version matches expected vulnerable version
if grep -q "$CURRENT_VERSION" "$VULNERABLE_FILE"; then
    # Replace vulnerable jQuery version with fixed version
    sed -i "s/$CURRENT_VERSION/$MIN_VERSION/g" "$VULNERABLE_FILE"
    
    # Verify the replacement was successful
    if ! grep -q "$MIN_VERSION" "$VULNERABLE_FILE"; then
        echo "Error: Failed to update jQuery version in $VULNERABLE_FILE" >&2
        exit 1
    fi
else
    echo "Error: Current version $CURRENT_VERSION not found in $VULNERABLE_FILE" >&2
    exit 1
fi
```