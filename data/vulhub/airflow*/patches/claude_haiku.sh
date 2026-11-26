```bash
#!/usr/bin/env bash
# Remediation: jQuery 1.7.2 (XSS, fixed in 1.9.0+) served by Flower on port 5555.
# Tier: patch_update. Replace the bundled jQuery 1.7.2 with jQuery 1.12.4 (same major
# version 1.x), rename it so the scanner no longer sees the 1.7.2 version in the URL,
# and update references to the old filename. No service restart is done here; the
# caller runs `docker restart`. Changes are written to the container filesystem.

set -u

export DEBIAN_FRONTEND=noninteractive

NEW_VER="1.12.4"
OLD_VER="1.7.2"
SEARCH_ROOTS="/usr/local /opt /srv"
TMP_DIR="$(mktemp -d /tmp/jquery-remediate.XXXXXX)"
TMP_JS="${TMP_DIR}/jquery-${NEW_VER}.min.js"
CLEANUP() { rm -rf "${TMP_DIR}"; }
trap CLEANUP EXIT

log() { printf '[remediate] %s\n' "$*"; }
fail() { printf '[remediate] ERROR: %s\n' "$*" >&2; exit 1; }

# 1. Locate vulnerable jQuery files (1.7.2) and any references to them.
mapfile -t VULN_FILES < <(
    for root in ${SEARCH_ROOTS}; do
        [ -d "${root}" ] || continue
        find "${root}" -type f -name "jquery-${OLD_VER}*.js" 2>/dev/null
    done
)

mapfile -t REF_FILES < <(
    for root in ${SEARCH_ROOTS}; do
        [ -d "${root}" ] || continue
        grep -rIl --exclude='*.pyc' "jquery-${OLD_VER}" "${root}" 2>/dev/null
    done
)

if [ "${#VULN_FILES[@]}" -eq 0 ] && [ "${#REF_FILES[@]}" -eq 0 ]; then
    fail "no jquery-${OLD_VER} files or references found under: ${SEARCH_ROOTS}"
fi

log "found ${#VULN_FILES[@]} vulnerable file(s) and ${#REF_FILES[@]} referencing file(s)"

# 2. Obtain the fixed jQuery build (upstream; verify it is really the expected version).
download_ok=0
for url in \
    "https://code.jquery.com/jquery-${NEW_VER}.min.js" \
    "https://cdnjs.cloudflare.com/ajax/libs/jquery/${NEW_VER}/jquery.min.js"; do
    if curl -fsSL --connect-timeout 15 --max-time 120 -o "${TMP_JS}" "${url}" 2>/dev/null; then
        if grep -q "jQuery v${NEW_VER}" "${TMP_JS}" 2>/dev/null; then
            download_ok=1
            log "downloaded jQuery ${NEW_VER} from ${url}"
            break
        fi
    fi
done

[ "${download_ok}" -eq 1 ] || fail "could not download and verify jQuery ${NEW_VER}"

# 3. Replace each vulnerable file with the fixed build, renamed to the new version.
#    Keep the original directory; write atomically via a temp copy then mv.
for f in "${VULN_FILES[@]}"; do
    [ -f "${f}" ] || continue
    dir="$(dirname "${f}")"
    base="$(basename "${f}")"
    new_base="${base//jquery-${OLD_VER}/jquery-${NEW_VER}}"
    new_path="${dir}/${new_base}"

    cp -f "${TMP_JS}" "${new_path}.tmp" || fail "cannot write ${new_path}.tmp"
    mv -f "${new_path}.tmp" "${new_path}" || fail "cannot install ${new_path}"
    chmod 0644 "${new_path}" 2>/dev/null || true

    if [ "${new_path}" != "${f}" ]; then
        rm -f "${f}" || fail "cannot remove old file ${f}"
    fi
    log "replaced ${f} -> ${new_path}"
done

# 4. Update references to the old filename so pages load the fixed file.
for f in "${REF_FILES[@]}"; do
    [ -f "${f}" ] || continue
    [ -w "${f}" ] || { log "skip read-only reference file ${f}"; continue; }
    sed -i "s/jquery-${OLD_VER}/jquery-${NEW_VER}/g" "${f}" \
        || fail "cannot update references in ${f}"
    log "updated references in ${f}"
done

# 5. Verify: no vulnerable filenames remain under the search roots.
remaining="$(
    for root in ${SEARCH_ROOTS}; do
        [ -d "${root}" ] || continue
        find "${root}" -type f -name "jquery-${OLD_VER}*.js" 2>/dev/null
    done
)"
if [ -n "${remaining}" ]; then
    fail "vulnerable jQuery files still present: ${remaining}"
fi

log "remediation complete: jQuery ${OLD_VER} replaced by ${NEW_VER}; restart the container to apply"
exit 0
```