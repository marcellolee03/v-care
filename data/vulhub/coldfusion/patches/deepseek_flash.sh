#!/bin/bash
# Remediate CVE-2010-2861 / Adobe APSB10-18 (ColdFusion Administrator
# directory traversal through CFIDE/administrator/enter.cfm) by removing the
# vulnerable administrator entry point from every ColdFusion web root.
set -u

ROOT="/opt/coldfusion8"
BACKUP="/root/coldfusion8-cve-2010-2861-backup"
STAMP="$(date +%s 2>/dev/null || echo 0)-$$"
mkdir -p "$BACKUP" 2>/dev/null || true
count=0

disable_file() {
    f="$1"
    [ -e "$f" ] || [ -L "$f" ] || return 0

    rel="${f#/}"
    safe="$(printf '%s' "$rel" | tr -c 'A-Za-z0-9._-' '_')"
    dst="$BACKUP/${safe}.${STAMP}"

    if mv -f -- "$f" "$dst" 2>/dev/null; then
        echo "Moved vulnerable file: $f -> $dst"
    elif rm -f -- "$f" 2>/dev/null; then
        echo "Removed vulnerable file: $f"
    else
        chmod 000 -- "$f" 2>/dev/null || true
        echo "Unable to move or remove vulnerable file: $f" >&2
    fi

    count=$((count + 1))
}

# Search the ColdFusion installation for the vulnerable administrator page.
while IFS= read -r -d '' f; do
    lc="$(printf '%s' "$f" | tr '[:upper:]' '[:lower:]')"
    case "$lc" in
        */cfide/administrator/enter.cfm)
            disable_file "$f"
            ;;
    esac
done < <(find "$ROOT" \( -type f -o -type l \) -iname 'enter.cfm' -print0 2>/dev/null)

# Cover the common case where the web root is a symlink outside the install root.
for extra in /var/www /srv /usr/local /home; do
    [ -d "$extra" ] || continue
    while IFS= read -r -d '' f; do
        lc="$(printf '%s' "$f" | tr '[:upper:]' '[:lower:]')"
        case "$lc" in
            */cfide/administrator/enter.cfm)
                disable_file "$f"
                ;;
        esac
    done < <(find "$extra" \( -type f -o -type l \) -iname 'enter.cfm' -print0 2>/dev/null)
done

# Fallback: if the page could not be located as a file, disable the entire
# ColdFusion Administrator web directory so the URL can no longer resolve.
if [ "$count" -eq 0 ]; then
    while IFS= read -r -d '' d; do
        lc="$(printf '%s' "$d" | tr '[:upper:]' '[:lower:]')"
        case "$lc" in
            */cfide/administrator)
                base="$(basename "$d")"
                dst="$BACKUP/${base}.${STAMP}"
                if mv -f -- "$d" "$dst" 2>/dev/null; then
                    echo "Disabled Administrator directory: $d -> $dst"
                fi
                ;;
        esac
    done < <(find "$ROOT" -type d -iname 'administrator' -print0 2>/dev/null)
fi

exit 0