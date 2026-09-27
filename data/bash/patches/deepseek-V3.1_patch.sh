```bash
#!/bin/bash

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

apache_dir="/etc/apache2"
enabled_sites_dir="$apache_dir/sites-enabled"
available_sites_dir="$apache_dir/sites-available"

if [ ! -d "$apache_dir" ]; then
    echo "Error: Apache directory not found at $apache_dir" >&2
    exit 1
fi

for site_config in "$enabled_sites_dir"/*; do
    [ -e "$site_config" ] || continue
    
    if grep -q "mod_cgi" "$site_config" 2>/dev/null || \
       grep -q "ScriptAlias" "$site_config" 2>/dev/null || \
       grep -q "\.cgi" "$site_config" 2>/dev/null; then
        
        if ! grep -q "mod_security" "$site_config" 2>/dev/null; then
            sed -i '/<Directory \/usr\/lib\/cgi-bin>/,/<\/Directory>/ {
                /Options/ s/$/ -Includes/
                /Options/! s/^/\tOptions -Includes\n/
            }' "$site_config" 2>/dev/null || true
        fi
    fi
done

if systemctl is-active --quiet apache2 2>/dev/null; then
    systemctl reload apache2
fi

exit 0
```