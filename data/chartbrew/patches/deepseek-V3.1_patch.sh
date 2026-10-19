```bash
#!/bin/bash
set -euo pipefail

# Verify root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Configuration parameters
SERVICE_NAME="grafana-server"  # Based on port 3000 default for Grafana
CONFIG_FILE="/etc/grafana/grafana.ini"
BACKUP_SUFFIX=".bak_$(date +%Y%m%d_%H%M%S)"

# Verify Grafana configuration exists
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "Error: Grafana config not found at ${CONFIG_FILE}" >&2
    exit 1
fi

# Create backup before modifications
cp "${CONFIG_FILE}" "${CONFIG_FILE}${BACKUP_SUFFIX}"

# Enable HTTPS and enforce it
sed -i -E '
/^\[server\]$/,/^\[/ {
    # Force HTTPS only
    s/^;(protocol) = (http|https)/\1 = https/
    s/^(protocol) = http/\1 = https/
    
    # Set HTTPS port
    s/^;(http_port) = .*/\1 = 443/
    s/^(http_port) = .*/\1 = 443/
    
    # Redirect HTTP to HTTPS
    s/^;(redirect_to_https) = .*/\1 = true/
    s/^(redirect_to_https) = .*/\1 = true/
    
    # Require SSL for cookies
    s/^;(cookie_secure) = .*/\1 = true/
    s/^(cookie_secure) = .*/\1 = true/
}
' "${CONFIG_FILE}"

# Configure SSL certificates (using self-signed as fallback)
if ! grep -q "^cert_file" "${CONFIG_FILE}" && ! grep -q "^;cert_file" "${CONFIG_FILE}"; then
    cat >> "${CONFIG_FILE}" << 'EOF'

# SSL Configuration
cert_file = /etc/grafana/ssl/cert.pem
cert_key = /etc/grafana/ssl/key.pem
EOF
fi

# Ensure SSL directory exists with secure permissions
SSL_DIR="/etc/grafana/ssl"
mkdir -p "${SSL_DIR}"
chmod 700 "${SSL_DIR}"

# Generate self-signed certificate if none exists
CERT_FILE="${SSL_DIR}/cert.pem"
KEY_FILE="${SSL_DIR}/key.pem"
if [ ! -f "${CERT_FILE}" ] || [ ! -f "${KEY_FILE}" ]; then
    # Check if OpenSSL is available
    if command -v openssl >/dev/null 2>&1; then
        openssl req -x509 -newkey rsa:4096 \
            -keyout "${KEY_FILE}" \
            -out "${CERT_FILE}" \
            -days 365 -nodes \
            -subj "/CN=$(hostname)" >/dev/null 2>&1
        chmod 600 "${KEY_FILE}"
        chmod 644 "${CERT_FILE}"
    else
        echo "Warning: OpenSSL not found. Please install SSL certificates manually." >&2
    fi
fi

# Restart Grafana to apply changes
if systemctl is-active --quiet "${SERVICE_NAME}"; then
    systemctl restart "${SERVICE_NAME}" >/dev/null 2>&1 || {
        echo "Error: Failed to restart ${SERVICE_NAME}" >&2
        exit 1
    }
fi

# Verify service is running
if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
    echo "Error: ${SERVICE_NAME} is not running after configuration changes" >&2
    exit 1
fi

exit 0
```