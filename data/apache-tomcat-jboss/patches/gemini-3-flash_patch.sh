```bash
#!/bin/bash
set -euo pipefail

# Verify root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Root privileges required." >&2
    exit 1
fi

# Vulnerability: CVE-2012-0874, CVE-2013-4810 (RCE via EJB/JMX Invoker Servlets)
# The mitigation strategy is to disable the deployment units (WAR/SAR) that 
# register the vulnerable EJBInvokerServlet and JMXInvokerServlet.

# Define search roots common to JBoss and Tomcat on Debian-based systems
readonly SEARCH_ROOTS=("/opt" "/var/lib" "/usr/share" "/usr/local")
readonly VULN_PATTERN="EJBInvokerServlet|JMXInvokerServlet"

for root in "${SEARCH_ROOTS[@]}"; do
    [ -d "$root" ] || continue
    
    # Locate all web.xml files containing the vulnerable servlet definitions
    find "$root" -name "web.xml" -type f 2>/dev/null | while read -r web_xml; do
        if grep -qE "$VULN_PATTERN" "$web_xml"; then
            
            # Identify the deployment artifact root (typically ending in .war or .sar)
            # Java EE structure dictates: <app_root>/WEB-INF/web.xml
            deploy_unit="${web_xml%/WEB-INF/web.xml}"
            
            # Idempotent mitigation: rename the artifact to prevent it from being served
            if [ -e "$deploy_unit" ] && [[ "$deploy_unit" != *.disabled ]]; then
                mv "$deploy_unit" "${deploy_unit}.disabled" 2>/dev/null
            fi
        fi
    done
done
```