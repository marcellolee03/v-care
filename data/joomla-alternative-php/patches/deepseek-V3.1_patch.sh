```bash
#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Error: Root privileges required" >&2
    exit 1
fi

JOOMLA_VERSION="3.4.2"
FIXED_VERSION="3.6.5"
JOOMLA_PATH="/var/www/html"

if [ ! -d "$JOOMLA_PATH" ]; then
    echo "Error: Joomla directory not found at $JOOMLA_PATH" >&2
    exit 1
fi

CONFIG_FILE="$JOOMLA_PATH/configuration.php"
BACKUP_FILE="$CONFIG_FILE.bak"

if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    
    if grep -q "allow_url_fopen" "$CONFIG_FILE"; then
        sed -i '/allow_url_fopen/s/1/0/' "$CONFIG_FILE"
    else
        echo -e "\npublic \$allow_url_fopen = '0';" >> "$CONFIG_FILE"
    fi
    
    if grep -q "sef_rewrite" "$CONFIG_FILE"; then
        sed -i '/sef_rewrite/s/1/0/' "$CONFIG_FILE"
    else
        echo -e "\npublic \$sef_rewrite = '0';" >> "$CONFIG_FILE"
    fi
    
    chown www-data:www-data "$CONFIG_FILE"
    chmod 640 "$CONFIG_FILE"
fi

UPLOADS_DIR="$JOOMLA_PATH/images"
if [ -d "$UPLOADS_DIR" ]; then
    chmod 750 "$UPLOADS_DIR"
    find "$UPLOADS_DIR" -type f -name "*.php*" -exec rm -f {} \;
fi

HTACCESS_FILE="$JOOMLA_PATH/.htaccess"
if [ ! -f "$HTACCESS_FILE" ]; then
    cat > "$HTACCESS_FILE" << 'EOF'
<Files ~ "\.(php|php3|php4|php5|phtml|pl|py|jsp|asp|sh|cgi)$">
    Order allow,deny
    Deny from all
</Files>
EOF
    chown www-data:www-data "$HTACCESS_FILE"
    chmod 644 "$HTACCESS_FILE"
fi

exit 0
```