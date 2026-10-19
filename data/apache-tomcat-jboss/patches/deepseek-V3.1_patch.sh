```bash
#!/bin/bash

# Surgical hardening script for CVE-2012-0874 and CVE-2013-4810
# Disables vulnerable EJBInvokerServlet and JMXInvokerServlet endpoints

set -euo pipefail

# Verify root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Primary Tomcat configuration location
TOMCAT_CONF_DIR="/etc/tomcat"
JBOSS_CONF_DIR="/usr/share/jboss"

# Function to disable servlet via configuration
disable_servlet() {
    local config_file="$1"
    local servlet_name="$2"
    
    if [ ! -f "$config_file" ]; then
        return 0
    fi
    
    # Check if servlet mapping exists
    if grep -q "$servlet_name" "$config_file"; then
        # Comment out servlet definitions and mappings
        sed -i "/$servlet_name/ s/^/<!-- /; /$servlet_name/ s/$/ -->/" "$config_file"
    fi
}

# Function to remove invoker directory
remove_invoker_access() {
    local webapp_dir="$1"
    local invoker_path="$webapp_dir/WEB-INF/web.xml"
    
    if [ -f "$invoker_path" ]; then
        # Comment out invoker servlet mappings in web.xml
        sed -i '/EJBInvokerServlet\|JMXInvokerServlet/ s/^/<!-- /; /EJBInvokerServlet\|JMXInvokerServlet/ s/$/ -->/' "$invoker_path"
    fi
}

# Main hardening routine
main() {
    echo "Applying RCE vulnerability mitigations..." >&2
    
    # Tomcat hardening
    if [ -d "$TOMCAT_CONF_DIR" ]; then
        for config in $(find "$TOMCAT_CONF_DIR" -name "web.xml" -type f); do
            disable_servlet "$config" "EJBInvokerServlet"
            disable_servlet "$config" "JMXInvokerServlet"
        done
    fi
    
    # JBoss hardening
    if [ -d "$JBOSS_CONF_DIR" ]; then
        for webapp in $(find "$JBOSS_CONF_DIR" -name "web.xml" -type f); do
            remove_invoker_access "$(dirname "$(dirname "$webapp")")"
        done
        
        # Also check server configuration
        for config in $(find "$JBOSS_CONF_DIR" -name "*.xml" -type f | grep -E "(server|standalone)"); do
            disable_servlet "$config" "invoker"
        done
    fi
    
    # Block direct access via web server configuration (if Apache/Nginx present)
    for webserver_conf in /etc/apache2/sites-available/* /etc/nginx/sites-available/* 2>/dev/null; do
        if [ -f "$webserver_conf" ]; then
            if grep -q "8080" "$webserver_conf"; then
                sed -i '/Location.*\/invoker\//i \    Deny from all' "$webserver_conf" 2>/dev/null || true
            fi
        fi
    done
    
    echo "Mitigations applied. Restart application server for changes to take effect." >&2
}

# Execute main function
main
```