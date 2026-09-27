```bash
#!/bin/bash

set -euo pipefail

# Verify root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Constants
CFIDE_PATH="/cfide/scripts/ajax/FCKeditor"
TOMCAT_CONF="/etc/tomcat*/server.xml"
APACHE_CONF="/etc/apache2/sites-enabled/*.conf"
NGINX_CONF="/etc/nginx/sites-enabled/*.conf"
BACKUP_SUFFIX=".bak_$(date +%Y%m%d_%H%M%S)"

# Function to check if URL is accessible
check_fckeditor() {
    if wget -q --method=HEAD "http://localhost:8500${CFIDE_PATH}" || \
       curl -s -f -I "http://localhost:8500${CFIDE_PATH}" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Function to disable via Apache/Nginx
disable_via_web_server() {
    local conf_pattern="$1"
    local server_name="$2"
    local modified=0
    
    for conf_file in $conf_pattern; do
        [ -f "$conf_file" ] || continue
        
        if grep -q "FCKeditor" "$conf_file" || grep -q "$CFIDE_PATH" "$conf_file"; then
            cp "$conf_file" "${conf_file}${BACKUP_SUFFIX}"
            
            awk -v path="$CFIDE_PATH" '
            /location.*FCKeditor/ || /Alias.*FCKeditor/ || /ScriptAlias.*FCKeditor/ {
                print "# DISABLED_FOR_SECURITY " $0 " # " strftime("%Y-%m-%d %H:%M:%S")
                next
            }
            { print }
            ' "$conf_file" > "${conf_file}.tmp" && mv "${conf_file}.tmp" "$conf_file"
            
            echo "Disabled FCKeditor in ${server_name} config: $conf_file"
            modified=1
        fi
    done
    
    if [ "$modified" -eq 1 ]; then
        case "$server_name" in
            apache) 
                apache2ctl -t >/dev/null 2>&1 && apache2ctl graceful >/dev/null 2>&1
                ;;
            nginx)
                nginx -t >/dev/null 2>&1 && nginx -s reload >/dev/null 2>&1
                ;;
        esac
    fi
}

# Function to disable via Tomcat
disable_via_tomcat() {
    for conf_file in $TOMCAT_CONF; do
        [ -f "$conf_file" ] || continue
        
        if grep -q "FCKeditor" "$conf_file"; then
            cp "$conf_file" "${conf_file}${BACKUP_SUFFIX}"
            
            sed -i '/FCKeditor/d; /\/cfide/d' "$conf_file"
            
            echo "Disabled FCKeditor in Tomcat config: $conf_file"
            systemctl restart tomcat* 2>/dev/null || service tomcat* restart 2>/dev/null
        fi
    done
}

# Main mitigation logic
if check_fckeditor; then
    echo "FCKeditor detected. Applying security controls..." >&2
    
    # Option 1: Block via web server configuration
    disable_via_web_server "$APACHE_CONF" "apache"
    disable_via_web_server "$NGINX_CONF" "nginx"
    disable_via_tomcat
    
    # Option 2: Apply filesystem restrictions as fallback
    if [ -d "/cfide" ]; then
        find "/cfide" -name "*FCKeditor*" -type f -exec chmod 000 {} \; 2>/dev/null || true
        find "/cfide" -name "*FCKeditor*" -type f -exec mv {} {}.disabled \; 2>/dev/null || true
    fi
    
    # Verify mitigation
    sleep 2
    if check_fckeditor; then
        echo "Warning: FCKeditor may still be accessible. Manual verification required." >&2
        exit 1
    fi
else
    echo "FCKeditor not detected or already mitigated." >&2
fi
```