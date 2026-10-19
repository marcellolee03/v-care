```bash
#!/bin/bash
set -euo pipefail

# Verify root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Error: Script must be run as root" >&2
    exit 1
fi

# Global configuration paths
NGINX_CONF="/etc/nginx/nginx.conf"
APACHE_CONF="/etc/apache2/apache2.conf"
SYSTEMD_JIRA_DIR="/etc/systemd/system"
JIRA_SERVICE="jira.service"
CONFLUENCE_SERVICE="confluence.service"

# Function to check if a web server is running
check_web_server() {
    if systemctl is-active --quiet nginx 2>/dev/null || \
       pgrep -x nginx >/dev/null 2>&1; then
        return 0
    elif systemctl is-active --quiet apache2 2>/dev/null || \
         pgrep -x apache2 >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to check if Jira/Confluence is running via systemd
check_atlassian_service() {
    local service_name=$1
    if [ -f "${SYSTEMD_JIRA_DIR}/${service_name}" ] && \
       systemctl is-active --quiet "${service_name}" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Function to add security headers via web server configuration
secure_web_server() {
    local conf_file=$1
    local server_type=$2
    
    # Check if configuration file exists
    if [ ! -f "$conf_file" ]; then
        return 0
    fi
    
    # Backup original configuration
    cp "$conf_file" "${conf_file}.bak-$(date +%Y%m%d%H%M%S)"
    
    # Add security headers based on server type
    if [ "$server_type" = "nginx" ]; then
        if ! grep -q "add_header X-Content-Type-Options" "$conf_file"; then
            sed -i '/http {/a\    add_header X-Content-Type-Options "nosniff";' "$conf_file"
            sed -i '/http {/a\    add_header X-Frame-Options "DENY";' "$conf_file"
        fi
    elif [ "$server_type" = "apache" ]; then
        if ! grep -q "Header set X-Content-Type-Options" "$conf_file"; then
            echo "Header set X-Content-Type-Options \"nosniff\"" >> "$conf_file"
            echo "Header set X-Frame-Options \"DENY\"" >> "$conf_file"
        fi
    fi
}

# Function to restrict Tomcat WEB-INF access (common for Atlassian products)
restrict_tomcat_access() {
    # Check if Tomcat is installed via systemd
    if systemctl list-unit-files | grep -q tomcat; then
        local tomcat_service=$(systemctl list-unit-files | grep tomcat | head -1 | awk '{print $1}')
        
        # Find Tomcat configuration directory
        local tomcat_conf=$(systemctl show -p FragmentPath "$tomcat_service" 2>/dev/null | cut -d= -f2)
        if [ -n "$tomcat_conf" ] && [ -f "$tomcat_conf" ]; then
            local tomcat_dir=$(dirname "$(dirname "$(readlink -f "$tomcat_conf")")")
            local context_xml="${tomcat_dir}/conf/context.xml"
            
            if [ -f "$context_xml" ]; then
                # Add resource restriction
                if ! grep -q "allowLinking=\"false\"" "$context_xml"; then
                    sed -i '/<Context>/a\    <Resources allowLinking="false" />' "$context_xml"
                fi
            fi
        fi
    fi
}

# Function to block vulnerable URL patterns via iptables
block_vulnerable_patterns() {
    # Check if iptables is available
    if ! command -v iptables >/dev/null 2>&1; then
        return 0
    fi
    
    # Block requests containing ;/WEB-INF/ pattern
    if ! iptables -C INPUT -p tcp --dport 8080 -m string --string "/;/WEB-INF/" --algo bm -j DROP 2>/dev/null; then
        iptables -A INPUT -p tcp --dport 8080 -m string --string "/;/WEB-INF/" --algo bm -j DROP
    fi
    
    # Block ;/ patterns in general for port 8080
    if ! iptables -C INPUT -p tcp --dport 8080 -m string --string "/;/" --algo bm -j DROP 2>/dev/null; then
        iptables -A INPUT -p tcp --dport 8080 -m string --string "/;/" --algo bm -j DROP
    fi
}

# Main execution logic
main() {
    echo "Applying security mitigations for CVE-2021-26085, CVE-2021-26086, CVE-2021-44138, CVE-2022-31656" >&2
    
    # 1. Secure web server configurations if present
    if [ -f "$NGINX_CONF" ]; then
        secure_web_server "$NGINX_CONF" "nginx"
    fi
    
    if [ -f "$APACHE_CONF" ]; then
        secure_web_server "$APACHE_CONF" "apache"
    fi
    
    # 2. Apply Tomcat-specific restrictions
    restrict_tomcat_access
    
    # 3. Block malicious patterns at network level
    block_vulnerable_patterns
    
    # 4. Restart affected services if they were running
    if check_web_server; then
        if systemctl is-active --quiet nginx 2>/dev/null; then
            systemctl reload nginx >/dev/null 2>&1 || true
        elif systemctl is-active --quiet apache2 2>/dev/null; then
            systemctl reload apache2 >/dev/null 2>&1 || true
        fi
    fi
    
    # 5. Restart Atlassian services if they were running
    for service in "$JIRA_SERVICE" "$CONFLUENCE_SERVICE"; do
        if check_atlassian_service "$service"; then
            systemctl restart "$service" >/dev/null 2>&1 || true
        fi
    done
    
    # Save iptables rules if iptables-persistent is available
    if command -v iptables-save >/dev/null 2>&1 && [ -d /etc/iptables ]; then
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
}

# Execute main function
main
```