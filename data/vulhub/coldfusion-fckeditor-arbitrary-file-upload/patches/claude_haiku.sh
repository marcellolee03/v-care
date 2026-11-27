#!/bin/bash
# Remediation: FCKeditor CFM connector arbitrary file upload (ColdFusion 8)
# Approach: the vulnerable feature (FCKeditor CFM connector) is not used by
# ColdFusion itself, so the connector script is removed from the web tree.
# Removed files are moved to a backup directory outside the webroot so the
# change can be reverted.

set -eu

INSTALL_ROOT="/opt/coldfusion8"
BACKUP_ROOT="/var/lib/remediation-backup/fckeditor-cfm-$(date +%Y%m%d%H%M%S)"
LOG_PREFIX="[fckeditor-remediation]"

log() {
    echo "${LOG_PREFIX} $*"
}

if [ ! -d "${INSTALL_ROOT}" ]; then
    log "ERROR: install root ${INSTALL_ROOT} not found"
    exit 1
fi

# Locate every FCKeditor CFM connector under the ColdFusion install tree.
# Matches the path layout .../FCKeditor/editor/filemanager/connectors/cfm/connector.cfm
FOUND_FILE="$(mktemp)"
trap 'rm -f "${FOUND_FILE}"' EXIT

find "${INSTALL_ROOT}" -type f -iname 'connector.cfm' \
    -path '*/filemanager/connectors/cfm/*' 2>/dev/null > "${FOUND_FILE}" || true

COUNT="$(wc -l < "${FOUND_FILE}" | tr -d ' ')"

if [ "${COUNT}" -eq 0 ]; then
    log "No FCKeditor CFM connector found under ${INSTALL_ROOT}; nothing to remove."
    exit 0
fi

log "Found ${COUNT} FCKeditor CFM connector file(s)."
mkdir -p "${BACKUP_ROOT}"

while IFS= read -r f; do
    [ -n "${f}" ] || continue
    # Preserve relative path inside the backup directory
    rel="${f#/}"
    dest="${BACKUP_ROOT}/${rel}"
    mkdir -p "$(dirname "${dest}")"
    mv -- "${f}" "${dest}"
    log "Removed from web tree: ${f} (backup: ${dest})"
done < "${FOUND_FILE}"

# Verify no connector.cfm remains in the web tree
REMAINING="$(find "${INSTALL_ROOT}" -type f -iname 'connector.cfm' \
    -path '*/filemanager/connectors/cfm/*' 2>/dev/null | wc -l | tr -d ' ')"

if [ "${REMAINING}" -ne 0 ]; then
    log "ERROR: ${REMAINING} connector file(s) still present"
    exit 1
fi

log "FCKeditor CFM connector removed. Vulnerable upload endpoint is no longer served."
exit 0