```bash
#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

readonly OPENSSL_CONFIG="/etc/ssl/openssl.cnf"
readonly DEFAULT_CIPHERS="HIGH:!aNULL:!MD5:!RC4:!3DES"
readonly TLS_MIN="TLSv1.2"

apply_openssl_config() {
    if [ -f "$OPENSSL_CONFIG" ]; then
        if ! grep -q "^MinProtocol.*$TLS_MIN" "$OPENSSL_CONFIG"; then
            sed -i "/^\[system_default_section\]/a MinProtocol = $TLS_MIN" "$OPENSSL_CONFIG"
        fi
        if ! grep -q "^CipherString.*$DEFAULT_CIPHERS" "$OPENSSL_CONFIG"; then
            sed -i "/^\[system_default_section\]/a CipherString = $DEFAULT_CIPHERS" "$OPENSSL_CONFIG"
        fi
    fi
}

update_service_configs() {
    local config_files=()
    config_files+=($(find /etc -name "*.conf" -type f | xargs grep -l "ssl_protocols\|ssl_ciphers\|SSLCipherSuite\|SSLProtocol" 2>/dev/null || true))
    config_files+=($(find /etc -name "*.cnf" -type f | xargs grep -l "ssl_protocols\|ssl_ciphers\|SSLCipherSuite\|SSLProtocol" 2>/dev/null || true))
    
    for config in "${config_files[@]}"; do
        if [ -f "$config" ]; then
            sed -i 's/ssl_protocols.*TLSv1\.0\|TLSv1\.1//g' "$config"
            sed -i 's/SSLProtocol.*-TLSv1\|-TLSv1\.1//g' "$config"
            sed -i 's/ssl_ciphers.*:\|;/\0 !aNULL:!MD5:!RC4:!3DES/g' "$config"
            sed -i 's/SSLCipherSuite.*/\0:!aNULL:!MD5:!RC4:!3DES/g' "$config"
        fi
    done
}

main() {
    apply_openssl_config
    update_service_configs
    echo "TLS configuration hardened. System services may need to be restarted." >&2
}

main "$@"
```