```bash
#!/bin/bash
set -euo pipefail

# Role: Senior System Security Engineer
# Description: Mitigates CVE-2012-1823 (PHP-CGI Argument Injection)
# Logic: Wraps the php-cgi binary to ignore query-string-injected CLI arguments 
# and hardens php.ini to prevent remote file inclusion.

# 1. Verify root privileges
[[ $EUID -eq 0 ]] || { echo "Error: root privileges required" >&2; exit 1; }

# 2. Harden PHP Configuration
# Path derived from the vulnerability context (phpinfo output)
PHP_INI="/usr/local/etc/php/php.ini"
PHP_DIR=$(dirname "$PHP_INI")

if [[ ! -d "$PHP_DIR" ]]; then
    mkdir -p "$PHP_DIR"
fi

if [[ ! -f "$PHP_INI" ]]; then
    touch "$PHP_INI"
fi

# Apply surgical configuration changes
# allow_url_include=Off prevents the RFI payload even if injection is attempted.
# cgi.force_redirect=1 prevents certain bypasses in CGI environments.
for setting in "allow_url_include=Off" "cgi.force_redirect=1"; do
    key="${setting%=*}"
    val="${setting#*=}"
    if grep -qE "^[; ]*$key" "$PHP_INI"; then
        sed -i "s|^[; ]*$key.*|$key = $val|" "$PHP_INI"
    else
        echo "$key = $val" >> "$PHP_INI"
    fi
done

# 3. Apply Binary Wrapper (Surgical Mitigation for CVE-2012-1823)
# The vulnerability exists because PHP-CGI parses query strings as command-line arguments.
# By inserting the '--' separator, we force the binary to treat injected flags as literal arguments/files.
CGI_BIN=$(command -v php-cgi || find /usr/local/bin /usr/bin /usr/local/sbin -name php-cgi 2>/dev/null | head -n 1 || true)

if [[ -n "$CGI_BIN" && -f "$CGI_BIN" && ! -L "$CGI_BIN" ]]; then
    # Idempotent check: ensure we haven't already moved the binary
    if [[ ! -f "${CGI_BIN}.real" ]]; then
        REAL_BIN="${CGI_BIN}.real"
        mv "$CGI_BIN" "$REAL_BIN"
        
        # Create the wrapper script
        # Using printf for a cleaner POSIX-compliant multi-line string
        printf '#!/bin/sh\nexec "%s" -- "$@"\n' "$REAL_BIN" > "$CGI_BIN"
        chmod 755 "$CGI_BIN"
        
        # If running as a persistent process (e.g. FastCGI), it would require a service restart.
        # However, standard CGI is invoked per-request, making this fix immediate.
    fi
fi

exit 0
```