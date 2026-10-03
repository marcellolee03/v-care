```bash
#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

tomcat_dir="/etc/tomcat* /var/lib/tomcat*"
servlets=("EJBInvokerServlet" "JMXInvokerServlet")

for dir in $tomcat_dir; do
    if [ -d "$dir" ]; then
        web_xml="${dir}/web.xml"
        if [ -f "$web_xml" ]; then
            for servlet in "${servlets[@]}"; do
                if grep -q "<servlet-name>${servlet}</servlet-name>" "$web_xml"; then
                    sed -i "/<servlet-name>${servlet}<\/servlet-name>/,/<\/servlet-mapping>/d" "$web_xml"
                fi
            done
        fi
    fi
done

exit 0
```