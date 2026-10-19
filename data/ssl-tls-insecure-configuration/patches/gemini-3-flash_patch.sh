```bash
#!/bin/bash
set -euo pipefail

# Verify root privileges
if [ "$EUID" -ne 0 ]; then
    exit 1
fi

# 1. Mitigate Postfix (Standard MTA for Port 25)
if command -v postconf >/dev/null 2>&1; then
    # Set minimum TLS version to 1.2 for both incoming and outgoing mail
    # Use >=TLSv1.2 syntax for modern Postfix or explicit exclusion for older versions
    postconf -e "smtpd_tls_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1"
    postconf -e "smtpd_tls_mandatory_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1"
    postconf -e "smtp_tls_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1"
    postconf -e "smtp_tls_mandatory_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1"

    # Reload service to apply changes if active
    if systemctl is-active --quiet postfix; then
        systemctl reload postfix
    fi
fi

# 2. System-wide OpenSSL Hardening (Covers multiple services on Pop!_OS/Ubuntu)
OPENSSL_CONF="/etc/ssl/openssl.cnf"
if [ -f "$OPENSSL_CONF" ]; then
    # Ensure MinProtocol is set to TLSv1.2 within the [system_default_sect]
    if grep -q "\[system_default_sect\]" "$OPENSSL_CONF"; then
        if grep -q "MinProtocol" "$OPENSSL_CONF"; then
            sed -i 's/^MinProtocol.*/MinProtocol = TLSv1.2/' "$OPENSSL_CONF"
        else
            sed -i '/\[system_default_sect\]/a MinProtocol = TLSv1.2' "$OPENSSL_CONF"
        fi
        
        # Also ensure CipherString security level is at least 2
        if grep -q "CipherString" "$OPENSSL_CONF"; then
            sed -i 's/^CipherString.*/CipherString = DEFAULT@SECLEVEL=2/' "$OPENSSL_CONF"
        else
            sed -i '/\[system_default_sect\]/a CipherString = DEFAULT@SECLEVEL=2' "$OPENSSL_CONF"
        fi
    fi
fi

# 3. Mitigate Exim4 (Alternative MTA)
if [ -d /etc/exim4 ] && command -v exim4 >/dev/null 2>&1; then
    EXIM_CONF="/etc/exim4/conf.d/main/03_exim4-config_tlsoptions"
    if [ -f "$EXIM_CONF" ]; then
        # Disable legacy protocols in Exim configuration
        if ! grep -q "tls_require_ciphers" "$EXIM_CONF"; then
            echo "tls_require_ciphers = HIGH:!SSLv2:!SSLv3:!TLSv1:!TLSv1.1" >> "$EXIM_CONF"
        else
            sed -i 's/tls_require_ciphers.*/tls_require_ciphers = HIGH:!SSLv2:!SSLv3:!TLSv1:!TLSv1.1/' "$EXIM_CONF"
        fi
        
        if systemctl is-active --quiet exim4; then
            update-exim4.conf
            systemctl restart exim4
        fi
    fi
fi
```