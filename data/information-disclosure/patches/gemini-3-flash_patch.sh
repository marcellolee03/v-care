```bash
#!/bin/bash

# Senior System Security Engineer - Linux Hardening Script
# Purpose: Mitigate /;/WEB-INF/ Information Disclosure (CVE-2021-26085, CVE-2021-26086, etc.)
# Targets: Atlassian Jira/Confluence and other Java-based web containers on Ubuntu 18.04
# Logic: Surgically injects a security constraint into web.xml to block path parameter bypasses.

set -euo pipefail

# Verify root privileges
if [[ "${EUID}" -ne 0 ]]; then
    echo "Error: Root privileges required." >&2
    exit 1
fi

# Define search path for common web application deployments
SEARCH_ROOT="/opt/atlassian"
[[ ! -d "$SEARCH_ROOT" ]] && SEARCH_ROOT="/opt"

# Locate targeted web.xml files
# Specifically targeting WEB-INF/web.xml where the vulnerability resides
TARGET_FILES=$(find "$SEARCH_ROOT" -name "web.xml" -path "*/WEB-INF/web.xml" 2>/dev/null || true)

for config_file in ${TARGET_FILES}; do
    # Idempotency: Verify if mitigation has already been applied
    if grep -q "HARDEN-PATH-BYPASS" "$config_file"; then
        continue
    fi

    # Create a surgical backup with preserved permissions
    cp -p "$config_file" "${config_file}.vulnerability_backup"

    # Surgical Injection Logic:
    # We add a <security-constraint> that explicitly denies access to normalized 
    # and unnormalized paths to WEB-INF and META-INF. 
    # This prevents URI bypasses using semicolons (path parameters).
    
    # We use sed to insert the block after the <display-name> element, 
    # ensuring it is placed within the root <web-app> node.
    sed -i '/<\/display-name>/a \
    <!-- HARDEN-PATH-BYPASS: CVE-2021-26085/6 mitigation --> \
    <security-constraint> \
        <web-resource-collection> \
            <web-resource-name>BlockPathBypass</web-resource-name> \
            <url-pattern>/*;/WEB-INF/*</url-pattern> \
            <url-pattern>/*;/META-INF/*</url-pattern> \
            <url-pattern>/;/WEB-INF/*</url-pattern> \
            <url-pattern>/;/META-INF/*</url-pattern> \
        </web-resource-collection> \
        <auth-constraint /> \
    </security-constraint>' "$config_file"
done

# Note: In a production lifecycle, a restart of the corresponding service 
# (e.g., 'systemctl restart jira') is required for changes to take effect.
exit 0
```