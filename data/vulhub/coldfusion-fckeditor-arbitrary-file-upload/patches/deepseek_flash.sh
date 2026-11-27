#!/bin/bash
set -euo pipefail

# Disable the FCKeditor file-manager connectors used by the reported endpoint:
# /cfide/scripts/ajax/FCKeditor/editor/filemanager/connectors/cfm/connector.cfm
# The ColdFusion service itself is left running and untouched.

search_roots=()
for d in /opt/coldfusion8 /var/www /srv /home /usr/local /root; do
    if [ -d "$d" ]; then
        search_roots+=("$d")
    fi
done

if [ "${#search_roots[@]}" -eq 0 ]; then
    search_roots=(/)
fi

disable_path() {
    local src="$1"
    local dst="${1}.disabled"
    local i=1

    if [ ! -e "$src" ] && [ ! -L "$src" ]; then
        return 0
    fi

    while [ -e "$dst" ] || [ -L "$dst" ]; do
        dst="${1}.disabled.${i}"
        i=$((i + 1))
    done

    mv -- "$src" "$dst"
}

# Disable every bundled FCKeditor connectors directory.
while IFS= read -r -d '' dir; do
    disable_path "$dir"
done < <(find -L "${search_roots[@]}" -type d -iname 'connectors' -ipath '*FCKeditor*' -print0 2>/dev/null)

# Fallback for non-standard layouts: disable the connector/upload scripts themselves.
while IFS= read -r -d '' file; do
    disable_path "$file"
done < <(find -L "${search_roots[@]}" -type f \
    \( -iname 'connector.cfm' -o -iname 'connector.cfc' -o -iname 'upload.cfm' \) \
    -ipath '*FCKeditor*' -print0 2>/dev/null)

# Explicit fallback for standard ColdFusion 8 document roots.
for p in \
    /opt/coldfusion8/cfusion/wwwroot/CFIDE/scripts/ajax/FCKeditor/editor/filemanager/connectors \
    /opt/coldfusion8/wwwroot/CFIDE/scripts/ajax/FCKeditor/editor/filemanager/connectors \
    /opt/coldfusion8/runtime/servers/cfusion/cfusion-ear/cfusion-war/CFIDE/scripts/ajax/FCKeditor/editor/filemanager/connectors
do
    disable_path "$p"
done