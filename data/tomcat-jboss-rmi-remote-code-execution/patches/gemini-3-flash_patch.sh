```bash
#!/bin/bash
# Mitigates CVE-2012-0874 and CVE-2013-4810 by removing unauthenticated
# access to EJBInvokerServlet and JMXInvokerServlet in JBoss/Tomcat.

set -euo pipefail

# Ensure the script is executed with root privileges
if [[ "$(id -u)" -ne 0 ]]; then
    exit 1
fi

# Locate web.xml files that contain the vulnerable servlet definitions.
# Pruning virtual filesystems /proc, /sys, /dev for efficiency.
find / -type d \( -path "/proc" -o -path "/sys" -o -path "/dev" \) -prune -o \
-type f -name "web.xml" -print 2>/dev/null | while read -r config_file; do
    
    # Check for the existence of the vulnerable servlets in the file
    if grep -qE "EJBInvokerServlet|JMXInvokerServlet" "$config_file"; then
        
        # Apply surgical removal of <servlet> and <servlet-mapping> blocks.
        # This logic uses sed to buffer blocks between tags and deletes them 
        # if they contain the targeted servlet names, ensuring idempotency.
        sed -i.bak '
            /<servlet>/ {
                :a
                N
                /<\/servlet>/! ba
                /EJBInvokerServlet\|JMXInvokerServlet/ d
            }
            /<servlet-mapping>/ {
                :b
                N
                /<\/servlet-mapping>/! bb
                /EJBInvokerServlet\|JMXInvokerServlet/ d
            }
        ' "$config_file"
        
    fi
done

exit 0
```