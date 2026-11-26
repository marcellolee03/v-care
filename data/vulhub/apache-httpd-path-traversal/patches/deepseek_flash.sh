#!/bin/bash
set -u

APACHE_ROOT="/usr/local/apache2"
CONF="$APACHE_ROOT/conf/httpd.conf"

if [ ! -f "$CONF" ]; then
    CONF=$(find "$APACHE_ROOT/conf" -maxdepth 2 -type f -name 'httpd.conf' -print -quit 2>/dev/null || true)
fi

if [ ! -f "${CONF:-}" ]; then
    exit 1
fi

if command -v realpath >/dev/null 2>&1; then
    CONF=$(realpath "$CONF")
fi

BACKUP="$CONF.cve-2021-41773.bak"
cp -p "$CONF" "$BACKUP" || exit 1

sanitize_root() {
    file="$1"
    tmp="$file.tmp.$$"

    awk '
    BEGIN { inroot=0; seen=0 }
    {
        low = tolower($0)

        if (!inroot && low ~ /^[[:space:]]*<directory[[:space:]]+["]?\/["]?[[:space:]]*>/) {
            print $0
            print "    AllowOverride none"
            print "    Require all denied"
            inroot = 1
            seen = 1
            next
        }

        if (inroot) {
            if (low ~ /^[[:space:]]*<\/directory[[:space:]]*>/) {
                inroot = 0
                print $0
                next
            }
            next
        }

        print $0
    }
    END {
        if (!seen) {
            print ""
            print "<Directory />"
            print "    AllowOverride none"
            print "    Require all denied"
            print "</Directory>"
        }
    }
    ' "$file" > "$tmp"

    if [ $? -eq 0 ]; then
        cat "$tmp" > "$file"
    fi
    rm -f "$tmp"
}

disable_alias_targets() {
    file="$1"
    perl -pi -e 's{^(\s*)(ScriptAlias\s+/cgi-bin\b|Alias\s+/icons\b)}{$1#$2}i' "$file" 2>/dev/null || true
}

REWRITE_ALREADY=0
if [ -x "$APACHE_ROOT/bin/httpd" ]; then
    if "$APACHE_ROOT/bin/httpd" -M 2>/dev/null | grep -q 'rewrite_module'; then
        REWRITE_ALREADY=1
    fi
fi

enable_rewrite() {
    file="$1"

    if [ "$REWRITE_ALREADY" = "1" ]; then
        return 0
    fi

    if [ ! -f "$APACHE_ROOT/modules/mod_rewrite.so" ]; then
        return 1
    fi

    if grep -Eq '^[[:space:]]*LoadModule[[:space:]][[:space:]]*rewrite_module([[:space:]]|$)' "$file"; then
        return 0
    fi

    if grep -Eq '^[[:space:]]*#[[:space:]]*LoadModule[[:space:]][[:space:]]*rewrite_module([[:space:]]|$)' "$file"; then
        sed -i -E 's@^[[:space:]]*#[[:space:]]*LoadModule[[:space:]][[:space:]]*rewrite_module[[:space:]][^[:space:]]*.*@LoadModule rewrite_module modules/mod_rewrite.so@' "$file"
    else
        printf '\nLoadModule rewrite_module %s/modules/mod_rewrite.so\n' "$APACHE_ROOT" >> "$file"
    fi

    return 0
}

add_filter() {
    file="$1"

    if grep -q 'CVE-2021-41773 mitigation' "$file"; then
        return 0
    fi

    block="/tmp/.cve-2021-41773-block.$$"
    cat > "$block" <<'EOF'

# CVE-2021-41773 / CVE-2021-42013 mitigation
<IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteCond %{THE_REQUEST} "[[:space:]][^[:space:]?]*(\.\.|%2e|%25)[^[:space:]?]*[[:space:]?]" [NC]
    RewriteRule ^ - [F,L]
</IfModule>
# end CVE-2021-41773 mitigation
EOF

    if grep -Eq '^[[:space:]]*LoadModule[[:space:]][[:space:]]*rewrite_module([[:space:]]|$)' "$file"; then
        sed -i -e "0,/^[[:space:]]*LoadModule[[:space:]][[:space:]]*rewrite_module/{
/^[[:space:]]*LoadModule[[:space:]][[:space:]]*rewrite_module/r $block
}" "$file"
    else
        cat "$block" >> "$file"
    fi

    rm -f "$block"

    if grep -q 'CVE-2021-41773 mitigation' "$file"; then
        return 0
    fi
    return 1
}

hide_version() {
    file="$1"

    if grep -q 'CVE-2021-41773 version disclosure' "$file"; then
        return 0
    fi

    cat >> "$file" <<'EOF'

# CVE-2021-41773 version disclosure reduction
ServerTokens Prod
ServerSignature Off
# end CVE-2021-41773 version disclosure reduction
EOF
}

apply_fallback() {
    cp -p "$BACKUP" "$CONF" || return 1

    sanitize_root "$CONF"
    disable_alias_targets "$CONF"

    perl -pi -e 's{^(\s*)(LoadModule\s+(?:cgi|cgid)_module\b)}{$1#$2}i' "$CONF" 2>/dev/null || true

    if ! grep -q 'CVE-2021-41773 fallback request filter' "$CONF"; then
        cat >> "$CONF" <<'EOF'

# CVE-2021-41773 fallback request filter
<LocationMatch "(?i)(%2e|%25|(^|/)\.\.(/|$))">
    Require all denied
</LocationMatch>
# end CVE-2021-41773 fallback request filter
EOF
    fi

    hide_version "$CONF"
    return 0
}

test_config() {
    bin="$APACHE_ROOT/bin/httpd"
    log="/tmp/.cve-2021-41773-httpd-test.$$"

    if [ -x "$bin" ]; then
        "$bin" -t -f "$CONF" >"$log" 2>&1
        rc=$?
        rm -f "$log"
        return $rc
    fi

    if command -v httpd >/dev/null 2>&1; then
        httpd -t -f "$CONF" >"$log" 2>&1
        rc=$?
        rm -f "$log"
        return $rc
    fi

    return 0
}

sanitize_root "$CONF"
disable_alias_targets "$CONF"

if enable_rewrite "$CONF" && add_filter "$CONF"; then
    hide_version "$CONF"

    if ! test_config; then
        apply_fallback
        if ! test_config; then
            cp -p "$BACKUP" "$CONF"
            exit 1
        fi
    fi
else
    apply_fallback
    if ! test_config; then
        cp -p "$BACKUP" "$CONF"
        exit 1
    fi
fi

exit 0