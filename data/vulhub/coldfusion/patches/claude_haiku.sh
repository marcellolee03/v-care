#!/bin/bash
# Remediation for CVE-2010-2861 (APSB10-18), ColdFusion directory traversal
# in /CFIDE/administrator/enter.cfm (locale parameter).
#
# Strategy: disable (tier 4). The vulnerable endpoint is the ColdFusion
# Administrator login page. The fix is to remove that page from the web
# root so the endpoint no longer exists after restart. The main server and
# the other application services do not depend on this page.

set -u

INSTALL_ROOT="/opt/coldfusion8"
TARGET_NAME="enter.cfm"
DISABLED_SUFFIX=".disabled"

log() {
    echo "[remediate] $*"
}

if [ ! -d "$INSTALL_ROOT" ]; then
    log "ERROR: install root $INSTALL_ROOT not found"
    exit 1
fi

# Locate every copy of enter.cfm under the CFIDE/administrator tree.
# Both expanded web roots and exploded EAR/WAR trees are covered.
mapfile -t TARGETS < <(find "$INSTALL_ROOT" -type f -name "$TARGET_NAME" \
    -path '*/CFIDE/administrator/*' 2>/dev/null)

if [ "${#TARGETS[@]}" -eq 0 ]; then
    log "ERROR: no $TARGET_NAME under CFIDE/administrator found in $INSTALL_ROOT"
    exit 1
fi

DISABLED_COUNT=0
for f in "${TARGETS[@]}"; do
    if mv -f -- "$f" "${f}${DISABLED_SUFFIX}"; then
        log "disabled: $f"
        DISABLED_COUNT=$((DISABLED_COUNT + 1))
    else
        log "ERROR: failed to disable $f"
    fi
done

# Remove compiled template caches for the same page so the server cannot
# keep serving a precompiled copy after restart.
CACHE_REMOVED=0
while IFS= read -r c; do
    if rm -f -- "$c"; then
        log "removed compiled cache: $c"
        CACHE_REMOVED=$((CACHE_REMOVED + 1))
    fi
done < <(find "$INSTALL_ROOT" -type f \( -iname '*administrator*enter*cfm*.class' \
    -o -iname '*administrator_enter_cfm*' -o -iname '*administrator*enter_cfm*.class' \) \
    2>/dev/null)

log "summary: disabled=$DISABLED_COUNT compiled_cache_removed=$CACHE_REMOVED"

if [ "$DISABLED_COUNT" -eq 0 ]; then
    log "ERROR: nothing was disabled"
    exit 1
fi

log "done. Restart the container to apply the change."
exit 0