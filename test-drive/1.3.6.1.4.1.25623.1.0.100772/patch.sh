#!/usr/bin/env bash
# CVE-2010-2861 / APSB10-18 (OID 1.3.6.1.4.1.25623.1.0.100772).
#
# Any template carrying the LOCALEFILE marker resolves the request-supplied
# `locale` into `resources/*_<locale>.xml` and reads it, so
#   locale=%00../../../../../../opt/coldfusion8/lib/password.properties%00a
# makes ColdFusion return the administrator password hash. The vulnerable code
# is not confined to one template: everything under CFIDE that renders a locale
# message carries it, and the scanning VT probes four different URLs.
#
# Adobe ships these CFIDE templates precompiled (Java class files with a .cfm
# extension), so a CFML guard cannot be prepended -- the code itself has to go.
# Blast radius is the ColdFusion Administrator, which this container serves but
# no application uses. Non-template assets (css, images, scripts, cfc) are kept.
set -u

WEBROOT=/opt/coldfusion8/wwwroot
BACKUP_DIR=/root/.cf8-cve-2010-2861-backup

if [ ! -d "$WEBROOT/CFIDE" ]; then
    echo "patch.sh: $WEBROOT/CFIDE not found - wrong container?" >&2
    exit 1
fi

mkdir -p "$BACKUP_DIR" 2>/dev/null || true

move_to_backup() {
    local path="$1"
    [ -e "$path" ] || [ -L "$path" ] || return 0

    local dest="$BACKUP_DIR/${path#/}"

    mkdir -p "$(dirname -- "$dest")" 2>/dev/null || true
    chattr -i -- "$path" 2>/dev/null || true

    if mv -f -- "$path" "$dest" 2>/dev/null; then
        return 0
    fi

    cp -a -- "$path" "$dest" 2>/dev/null || true
    rm -f -- "$path" 2>/dev/null || true
}

# 1. Every template that turns a request locale into a file path. Matched on the
#    marker rather than on a URL list, so including templates are covered too.
while IFS= read -r -d '' file; do
    move_to_backup "$file"
done < <(grep -rlZa 'LOCALEFILE' "$WEBROOT" --include='*.cfm' 2>/dev/null)

# 2. The rest of the administrator-side templates. Some (the login page, the L10N
#    tool) do not carry the marker themselves -- they reach the vulnerable code
#    through an include -- and leaving them behind leaves admin pages that used
#    to be gated by the now-removed administrator/Application.cfm answering
#    unauthenticated.
for dir in administrator componentutils wizards; do
    while IFS= read -r -d '' file; do
        move_to_backup "$file"
    done < <(find "$WEBROOT/CFIDE/$dir" -type f -name '*.cfm' -print0 2>/dev/null)
done

# 3. Fail loudly rather than leaving the traversal reachable.
left=$(grep -rla 'LOCALEFILE' "$WEBROOT" --include='*.cfm' 2>/dev/null | wc -l)
if [ "$left" -ne 0 ]; then
    echo "patch.sh: $left template(s) still carry the locale resolver" >&2
    exit 1
fi

for url in administrator/enter.cfm \
           wizards/common/_logintowizard.cfm \
           administrator/archives/index.cfm \
           administrator/entman/index.cfm; do
    if [ -e "$WEBROOT/CFIDE/$url" ]; then
        echo "patch.sh: $url still present" >&2
        exit 1
    fi
done
