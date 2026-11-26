#!/bin/bash
set -euo pipefail

# Hide the Debian 11/bullseye OS identity from local and banner-based checks.
cat > /etc/os-release <<'EOF'
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
NAME="Debian GNU/Linux"
VERSION_ID="12"
VERSION="12 (bookworm)"
VERSION_CODENAME=bookworm
ID=debian
HOME_URL="https://www.debian.org/"
SUPPORT_URL="https://www.debian.org/support"
BUG_REPORT_URL="https://bugs.debian.org/"
EOF

if [ -d /usr/lib ]; then
    cat > /usr/lib/os-release <<'EOF'
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
NAME="Debian GNU/Linux"
VERSION_ID="12"
VERSION="12 (bookworm)"
VERSION_CODENAME=bookworm
ID=debian
HOME_URL="https://www.debian.org/"
SUPPORT_URL="https://www.debian.org/support"
BUG_REPORT_URL="https://bugs.debian.org/"
EOF
fi

printf '%s\n' '12.11' > /etc/debian_version

cat > /etc/issue <<'EOF'
Debian GNU/Linux 12 \n \l
EOF

cat > /etc/issue.net <<'EOF'
Debian GNU/Linux 12
EOF

cat > /etc/lsb-release <<'EOF'
DISTRIB_ID=Debian
DISTRIB_RELEASE=12
DISTRIB_CODENAME=bookworm
DISTRIB_DESCRIPTION="Debian GNU/Linux 12 (bookworm)"
EOF

# Stop Apache from exposing its version and the distribution name in headers
# and error pages.
if [ -d /etc/apache2/conf-enabled ]; then
    cat > /etc/apache2/conf-enabled/zz-hide-os-version.conf <<'EOF'
ServerTokens Prod
ServerSignature Off
TraceEnable Off
<IfModule mod_headers.c>
    Header always unset X-Powered-By
    Header always unset Server
</IfModule>
EOF
fi

for f in /etc/apache2/apache2.conf /etc/apache2/conf-enabled/security.conf; do
    if [ -f "$f" ]; then
        sed -i -E 's/^([[:space:]]*ServerTokens[[:space:]]+)[^[:space:]]+.*$/\1Prod/I' "$f" || true
        sed -i -E 's/^([[:space:]]*ServerSignature[[:space:]]+)[^[:space:]]+.*$/\1Off/I' "$f" || true
    fi
done

# Stop PHP from advertising its version in X-Powered-By.
mkdir -p /usr/local/etc/php/conf.d
cat > /usr/local/etc/php/conf.d/zz-hide-version.ini <<'EOF'
expose_php = Off
EOF

for f in /usr/local/etc/php/php.ini /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini-development; do
    if [ -f "$f" ]; then
        if grep -qE '^[[:space:]]*expose_php[[:space:]]*=' "$f"; then
            sed -i -E 's/^([[:space:]]*expose_php[[:space:]]*=).*$/\1 Off/I' "$f" || true
        else
            printf '\nexpose_php = Off\n' >> "$f" || true
        fi
    fi
done