```bash
#!/bin/bash

# Enable strict error handling
set -euo pipefail

# Verify root privileges
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Configuration file paths
TOMCAT_CONF="/etc/tomcat9/server.xml"
SYSTEM_CONF="/etc/systemd/system/tomcat9.service.d/override.conf"

# Function to check if Tomcat is running on port 8080
check_tomcat_running() {
    if ! ss -tlnp | grep -q ':8080'; then
        echo "Error: Tomcat not detected on port 8080" >&2
        return 1
    fi
}

# Function to enable SSL in Tomcat configuration
configure_tomcat_ssl() {
    local connector_found=0
    
    # Check for existing SSL connector
    if grep -q 'Connector.*SSLEnabled="true"' "$TOMCAT_CONF"; then
        echo "SSL connector already configured in $TOMCAT_CONF"
        connector_found=1
        return 0
    fi
    
    # Create backup of original configuration
    cp "$TOMCAT_CONF" "${TOMCAT_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Find and modify HTTP connector to redirect to HTTPS
    if grep -q 'Connector.*port="8080"' "$TOMCAT_CONF"; then
        connector_found=1
        
        # Comment out existing HTTP connector
        sed -i '/Connector.*port="8080"/s/^/<!-- HTTP connector disabled - Redirecting to HTTPS -->\n<!-- /' "$TOMCAT_CONF"
        sed -i '/Connector.*port="8080"/s/$/ -->/' "$TOMCAT_CONF"
        
        # Add SSL connector configuration
        sed -i '/<!-- Define an SSL Connector/q' "$TOMCAT_CONF"
        
        cat >> "$TOMCAT_CONF" << 'EOF'
    <!-- Define an SSL/TLS Connector on port 8443 -->
    <Connector port="8443" protocol="org.apache.coyote.http11.Http11NioProtocol"
               maxThreads="150" SSLEnabled="true">
        <SSLHostConfig>
            <Certificate certificateKeystoreFile="/etc/tomcat9/keystore.p12"
                         certificateKeystorePassword="changeit"
                         type="RSA" />
        </SSLHostConfig>
    </Connector>
EOF
    fi
    
    if [[ $connector_found -eq 0 ]]; then
        echo "Error: Could not find Tomcat connector configuration" >&2
        return 1
    fi
}

# Function to create self-signed certificate
create_self_signed_cert() {
    local keystore_path="/etc/tomcat9/keystore.p12"
    
    if [[ -f "$keystore_path" ]]; then
        echo "Keystore already exists at $keystore_path"
        return 0
    fi
    
    # Generate self-signed certificate
    openssl req -newkey rsa:2048 -nodes -keyout /etc/tomcat9/server.key \
                -x509 -days 365 -out /etc/tomcat9/server.crt \
                -subj "/CN=fedora/O=Organization/C=US" 2>/dev/null
    
    # Create PKCS12 keystore
    openssl pkcs12 -export -in /etc/tomcat9/server.crt \
                   -inkey /etc/tomcat9/server.key \
                   -out "$keystore_path" \
                   -name "tomcat-ssl" \
                   -password pass:changeit 2>/dev/null
    
    # Set proper permissions
    chmod 600 /etc/tomcat9/server.key
    chmod 600 /etc/tomcat9/server.crt
    chmod 600 "$keystore_path"
    chown tomcat:tomcat "$keystore_path"
}

# Function to configure systemd override for redirect
configure_systemd_redirect() {
    mkdir -p "/etc/systemd/system/tomcat9.service.d"
    
    cat > "$SYSTEM_CONF" << 'EOF'
[Service]
# Environment variable to enforce HTTPS
Environment="CATALINA_OPTS=-Dorg.apache.catalina.connector.RECYCLE_FACADES=true"
EOF
}

# Function to configure HTTP to HTTPS redirect in web.xml
configure_webapp_redirect() {
    local webapps_dir="/var/lib/tomcat9/webapps"
    local cas_webapp=$(find "$webapps_dir" -name "cas" -type d | head -1)
    
    if [[ -n "$cas_webapp" ]]; then
        local web_xml="${cas_webapp}/WEB-INF/web.xml"
        
        if [[ -f "$web_xml" ]]; then
            # Add security constraint if not already present
            if ! grep -q '<security-constraint>' "$web_xml"; then
                sed -i '/<\/web-app>/i\
    <security-constraint>\
        <web-resource-collection>\
            <web-resource-name>Protected Context</web-resource-name>\
            <url-pattern>/*</url-pattern>\
        </web-resource-collection>\
        <user-data-constraint>\
            <transport-guarantee>CONFIDENTIAL</transport-guarantee>\
        </user-data-constraint>\
    </security-constraint>' "$web_xml"
            fi
        fi
    fi
}

# Main execution flow
main() {
    # Verify Tomcat is running
    check_tomcat_running
    
    # Configure Tomcat SSL
    configure_tomcat_ssl
    
    # Create SSL certificate
    create_self_signed_cert
    
    # Configure systemd override
    configure_systemd_redirect
    
    # Configure web application redirect
    configure_webapp_redirect
    
    # Restart Tomcat to apply changes
    systemctl daemon-reload
    systemctl restart tomcat9.service
    
    # Verify service is running
    if systemctl is-active --quiet tomcat9.service; then
        echo "Tomcat successfully restarted with SSL enabled"
    else
        echo "Error: Tomcat failed to restart" >&2
        exit 1
    fi
}

# Execute main function
main
```