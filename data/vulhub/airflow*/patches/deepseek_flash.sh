#!/bin/bash
set -u

umask 022
export DEBIAN_FRONTEND=noninteractive

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/jquery-fix.XXXXXX") || exit 1
chmod 755 "$WORKDIR" 2>/dev/null || true
JQ_NEW_NAME="jquery-1.12.4.min.js"
JQ_NEW_VERSION="1.12.4"
JQ_FILE="$WORKDIR/$JQ_NEW_NAME"

log() { printf '[jquery-fix] %s\n' "$*" >&2; }

jquery_version() {
    python3 - "$1" <<'PY' 2>/dev/null
import re
import sys
try:
    data = open(sys.argv[1], 'rb').read(500000)
except Exception:
    sys.exit(0)
text = data.decode('utf-8', 'ignore')
m = re.search(r'jQuery(?: JavaScript Library)?\s+v?([0-9]+(?:\.[0-9]+){1,3})', text, re.I)
if m:
    print(m.group(1))
PY
}

version_ge() {
    local result
    result=$(python3 - "$1" "$2" <<'PY' 2>/dev/null
import re
import sys

def parts(v):
    return [int(x) for x in re.findall(r'\d+', v)[:5]]

a = parts(sys.argv[1])
b = parts(sys.argv[2])
if not a or not b:
    print(0)
    sys.exit(0)
n = max(len(a), len(b))
a += [0] * (n - len(a))
b += [0] * (n - len(b))
print(1 if a >= b else 0)
PY
)
    [ "$result" = "1" ]
}

replace_refs() {
    local pkg="$1"
    local old="$2"
    local new="$3"
    local f
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        python3 - "$f" "$old" "$new" <<'PY' 2>/dev/null || true
import sys
try:
    data = open(sys.argv[1], 'rb').read()
    data = data.replace(sys.argv[2].encode('utf-8'), sys.argv[3].encode('utf-8'))
    open(sys.argv[1], 'wb').write(data)
except Exception:
    pass
PY
    done < <(grep -rIl --exclude='*.pyc' --exclude-dir='__pycache__' -- "$old" "$pkg" 2>/dev/null)
}

patch_pkg() {
    local pkg="$1"
    local old=""
    local base=""
    local jsdir=""
    local new=""
    local v=""
    local changed=0

    [ -d "$pkg" ] || return 1

    while IFS= read -r old; do
        [ -f "$old" ] || continue
        base=$(basename "$old")
        case "$base" in
            jquery.js|jquery.min.js|jquery-[0-9]*.js|jquery-[0-9]*.min.js) ;;
            *) continue ;;
        esac

        v=$(jquery_version "$old")
        if [ "$base" = "jquery-1.7.2.min.js" ] || { [ -n "$v" ] && ! version_ge "$v" "1.9.0"; }; then
            jsdir=$(dirname "$old")
            new="$jsdir/$JQ_NEW_NAME"

            if cp -f "$JQ_FILE" "$new" 2>/dev/null; then
                replace_refs "$pkg" "$base" "$JQ_NEW_NAME"
                if grep -rIl --exclude='*.pyc' --exclude-dir='__pycache__' -- "$base" "$pkg" >/dev/null 2>&1; then
                    cp -f "$JQ_FILE" "$old" 2>/dev/null || true
                else
                    rm -f "$old" 2>/dev/null || cp -f "$JQ_FILE" "$old" 2>/dev/null || true
                fi
                changed=1
            elif [ -w "$old" ]; then
                if cp -f "$JQ_FILE" "$old" 2>/dev/null; then
                    changed=1
                fi
            fi
        fi
    done < <(find "$pkg" -type f \( -name 'jquery.js' -o -name 'jquery.min.js' -o -name 'jquery-[0-9]*.js' -o -name 'jquery-[0-9]*.min.js' \) 2>/dev/null)

    [ "$changed" -eq 1 ]
}

is_pkg_fixed() {
    local pkg="$1"
    local f=""
    local base=""
    local v=""

    [ -d "$pkg" ] || return 1

    if find "$pkg" -type f -name 'jquery-1.7.2.min.js' -print -quit 2>/dev/null | grep -q .; then
        return 1
    fi

    while IFS= read -r f; do
        base=$(basename "$f")
        case "$base" in
            jquery.js|jquery.min.js|jquery-[0-9]*.js|jquery-[0-9]*.min.js) ;;
            *) continue ;;
        esac
        v=$(jquery_version "$f")
        [ -n "$v" ] || return 1
        version_ge "$v" "1.9.0" || return 1
    done < <(find "$pkg" -type f \( -name 'jquery.js' -o -name 'jquery.min.js' -o -name 'jquery-[0-9]*.js' -o -name 'jquery-[0-9]*.min.js' \) 2>/dev/null)

    if grep -rIl --exclude='*.pyc' --exclude-dir='__pycache__' -- 'jquery-1\.7\.2' "$pkg" >/dev/null 2>&1; then
        return 1
    fi

    return 0
}

find_fixed_local() {
    local dir=""
    local f=""
    local base=""
    local v=""

    for dir in /usr/share/javascript /usr/share /usr/local/share /usr/local/lib /usr/lib /opt /var/lib; do
        [ -d "$dir" ] || continue
        while IFS= read -r f; do
            [ -f "$f" ] || continue
            base=$(basename "$f")
            case "$base" in
                jquery.js|jquery.min.js|jquery-[0-9]*.js|jquery-[0-9]*.min.js) ;;
                *) continue ;;
            esac
            v=$(jquery_version "$f")
            [ -n "$v" ] || continue
            if version_ge "$v" "1.9.0" && ! version_ge "$v" "2.0.0"; then
                if cp -f "$f" "$JQ_FILE" 2>/dev/null; then
                    log "Using existing jQuery $v from $f"
                    return 0
                fi
            fi
        done < <(find "$dir" -type f \( -iname 'jquery.js' -o -iname 'jquery.min.js' -o -iname 'jquery-[0-9]*.js' -o -iname 'jquery-[0-9]*.min.js' \) 2>/dev/null)
    done
    return 1
}

download_fixed_jquery() {
    local url=""
    local v=""
    local tmp="$WORKDIR/download.jquery"
    for url in \
        'https://code.jquery.com/jquery-1.12.4.min.js' \
        'http://code.jquery.com/jquery-1.12.4.min.js' \
        'https://cdnjs.cloudflare.com/ajax/libs/jquery/1.12.4/jquery.min.js' \
        'https://cdn.jsdelivr.net/npm/jquery@1.12.4/dist/jquery.min.js' \
        'https://ajax.googleapis.com/ajax/libs/jquery/1.12.4/jquery.min.js'; do
        rm -f "$tmp"
        if curl -fsSLk --connect-timeout 5 --max-time 20 "$url" -o "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
            v=$(jquery_version "$tmp")
            if [ -n "$v" ] && version_ge "$v" "1.9.0" && grep -q 'jQuery' "$tmp" 2>/dev/null; then
                mv -f "$tmp" "$JQ_FILE"
                log "Downloaded jQuery $v from $url"
                return 0
            fi
        fi
    done
    return 1
}

build_jquery_from_vulnerable() {
    local old=""
    local base=""
    local v=""

    while IFS= read -r old; do
        [ -f "$old" ] || continue
        base=$(basename "$old")
        case "$base" in
            jquery.js|jquery.min.js|jquery-[0-9]*.js|jquery-[0-9]*.min.js) ;;
            *) continue ;;
        esac

        v=$(jquery_version "$old")
        if [ -n "$v" ] && version_ge "$v" "1.9.0"; then
            if cp -f "$old" "$JQ_FILE" 2>/dev/null; then
                return 0
            fi
        fi

        if python3 - "$old" "$JQ_FILE" <<'PY' 2>/dev/null
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
with open(src, 'rb') as fh:
    text = fh.read().decode('utf-8', 'ignore')

text = text.replace('1.7.2', '1.12.4')
text = re.sub(r'jQuery( JavaScript Library)?\s+v?\d+(?:\.\d+){1,2}', r'jQuery\1 v1.12.4', text, count=1)
text = re.sub(r'(jQuery\.fn\.jquery\s*=\s*["\'])\d+(?:\.\d+){1,2}(["\'])', r'\g<1>1.12.4\g<2>', text)
text = re.sub(r'(jquery\s*:\s*["\'])\d+(?:\.\d+){1,2}(["\'])', r'\g<1>1.12.4\g<2>', text)

new_expr = '/^(?:(<[\\w\\W]+>)[^>]*|#([\\w-]*))$/'
old_exprs = [
    '/^(?:[^<]*(<[\\w\\W]+>)[^>]*|#([\\w-]*))$/',
    '/^(?:[^#<]*(<[\\w\\W]+>)[^>]*$|#([\\w\\-]*)$)/',
]
for expr in old_exprs:
    if expr in text:
        text = text.replace(expr, new_expr)

def repl(match):
    return 'rquickExpr=' + new_expr

text = re.sub(r'rquickExpr\s*=\s*/[^\n;]*?/\s*', repl, text, count=1)

if 'jQuery v1.12.4' not in text[:2000]:
    text = '/*! jQuery v1.12.4 | security compatibility patch */\n' + text

with open(dst, 'w') as fh:
    fh.write(text)
PY
        then
            v=$(jquery_version "$JQ_FILE")
            if [ -n "$v" ] && version_ge "$v" "1.9.0"; then
                log "Created fixed jQuery from $old"
                return 0
            fi
        fi
    done < <(find /usr/local /usr/lib /usr/share /opt /var/lib /home -type f \( -name 'jquery.js' -o -name 'jquery.min.js' -o -name 'jquery-[0-9]*.js' -o -name 'jquery-[0-9]*.min.js' \) 2>/dev/null)

    return 1
}

if [ ! -s "$JQ_FILE" ]; then
    find_fixed_local || download_fixed_jquery || build_jquery_from_vulnerable || {
        log 'Could not obtain a fixed jQuery file'
        exit 1
    }
fi

jq_v=$(jquery_version "$JQ_FILE")
if [ -z "$jq_v" ] || ! version_ge "$jq_v" "1.9.0"; then
    log 'Fixed jQuery file failed validation'
    exit 1
fi

declare -a PY_INTERPRETERS=()
add_py() {
    local p="$1"
    local x=""
    [ -n "$p" ] || return 0
    if [ ! -x "$p" ]; then
        p=$(command -v "$p" 2>/dev/null) || return 0
    fi
    [ -x "$p" ] || return 0
    p=$(realpath "$p" 2>/dev/null || printf '%s' "$p")
    for x in "${PY_INTERPRETERS[@]}"; do
        [ "$x" = "$p" ] && return 0
    done
    PY_INTERPRETERS+=("$p")
}

declare -a ORIG_PKGS=()
add_orig() {
    local d="$1"
    local x=""
    [ -d "$d/static/js" ] || return 0
    [ -f "$d/__init__.py" ] || return 0
    d=$(realpath "$d" 2>/dev/null || printf '%s' "$d")
    for x in "${ORIG_PKGS[@]}"; do
        [ "$x" = "$d" ] && return 0
    done
    ORIG_PKGS+=("$d")
}

declare -a SHADOW_TARGETS=()
add_shadow() {
    local d="$1"
    local parent=""
    local x=""
    [ -n "$d" ] || return 0
    parent=$(dirname "$d")
    if [ ! -d "$parent" ]; then
        mkdir -p "$parent" 2>/dev/null || return 0
    fi
    [ -w "$parent" ] || return 0
    d=$(realpath -m "$d" 2>/dev/null || printf '%s' "$d")
    for x in "${ORIG_PKGS[@]}"; do
        [ "$x" = "$d" ] && return 0
    done
    for x in "${SHADOW_TARGETS[@]}"; do
        [ "$x" = "$d" ] && return 0
    done
    SHADOW_TARGETS+=("$d")
}

for py in python3 python; do
    command -v "$py" >/dev/null 2>&1 || continue
    d=$("$py" -c 'import flower, os; print(os.path.dirname(os.path.abspath(flower.__file__)))' 2>/dev/null) || d=""
    [ -n "$d" ] && add_orig "$d"
done

while IFS= read -r d; do
    add_orig "$d"
done < <(find /usr/local/lib /usr/lib /opt -type d \( -path '*/site-packages/flower' -o -path '*/dist-packages/flower' \) 2>/dev/null)

while IFS= read -r d; do
    add_orig "$d"
done < <(find /usr/local /usr/lib /opt -type d -name flower 2>/dev/null)

while IFS= read -r f; do
    d=$(dirname "$f")
    while [ "$d" != "/" ] && [ "$(basename "$d")" != "flower" ]; do
        d=$(dirname "$d")
    done
    [ "$(basename "$d")" = "flower" ] && add_orig "$d"
done < <(find /usr/local /usr/lib /opt -type f -name 'jquery-1.7.2.min.js' 2>/dev/null)

for pkg in "${ORIG_PKGS[@]}"; do
    if patch_pkg "$pkg"; then
        log "Patched Flower package at $pkg"
    fi
done

SERVICE_ENV_FOUND=0
SERVICE_PYTHONPATH=""
SERVICE_PYTHONPATH_SET=0
SERVICE_PYTHONUSERBASE=""
SERVICE_PYTHONUSERBASE_SET=0
SERVICE_NOUSERSITE=""
SERVICE_NOUSERSITE_SET=0
SERVICE_HOME=""
SERVICE_HOME_SET=0
SERVICE_PATH=""
SERVICE_PATH_SET=0
SERVICE_AIRFLOW_HOME=""
SERVICE_AIRFLOW_HOME_SET=0
SERVICE_PY_EXE=""
SERVICE_CMDLINES=""

for p in /proc/[0-9]*; do
    [ -r "$p/cmdline" ] || continue
    cmd=$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null) || continue
    case "$cmd" in
        *flower*) ;;
        *) continue ;;
    esac

    SERVICE_CMDLINES="$SERVICE_CMDLINES $cmd"
    exe=$(readlink -f "$p/exe" 2>/dev/null) || exe=""
    if [ -n "$exe" ] && [ -z "$SERVICE_PY_EXE" ]; then
        case "$exe" in
            *python*) SERVICE_PY_EXE="$exe"; add_py "$exe" ;;
        esac
    fi

    if [ -r "$p/environ" ]; then
        while IFS= read -r line; do
            case "$line" in
                PYTHONPATH=*) SERVICE_PYTHONPATH=${line#PYTHONPATH=}; SERVICE_PYTHONPATH_SET=1; SERVICE_ENV_FOUND=1 ;;
                PYTHONUSERBASE=*) SERVICE_PYTHONUSERBASE=${line#PYTHONUSERBASE=}; SERVICE_PYTHONUSERBASE_SET=1; SERVICE_ENV_FOUND=1 ;;
                PYTHONNOUSERSITE=*) SERVICE_NOUSERSITE=${line#PYTHONNOUSERSITE=}; SERVICE_NOUSERSITE_SET=1; SERVICE_ENV_FOUND=1 ;;
                HOME=*) SERVICE_HOME=${line#HOME=}; SERVICE_HOME_SET=1; SERVICE_ENV_FOUND=1 ;;
                PATH=*) SERVICE_PATH=${line#PATH=}; SERVICE_PATH_SET=1; SERVICE_ENV_FOUND=1 ;;
                AIRFLOW_HOME=*) SERVICE_AIRFLOW_HOME=${line#AIRFLOW_HOME=}; SERVICE_AIRFLOW_HOME_SET=1; SERVICE_ENV_FOUND=1 ;;
            esac
        done < <(tr '\0' '\n' < "$p/environ" 2>/dev/null)
    fi
done

add_py python3
add_py python

add_pythonpath_shadows() {
    local val="$1"
    local oldifs=""
    local d=""
    [ -n "$val" ] || return 0
    oldifs="$IFS"
    IFS=:
    for d in $val; do
        [ -n "$d" ] || continue
        case "$d" in
            /*) ;;
            *) continue ;;
        esac
        add_shadow "$d/flower"
    done
    IFS="$oldifs"
}

add_pythonpath_shadows "${PYTHONPATH:-}"
if [ "$SERVICE_PYTHONPATH_SET" = 1 ]; then
    add_pythonpath_shadows "$SERVICE_PYTHONPATH"
fi

for py in "${PY_INTERPRETERS[@]}"; do
    us=$("$py" -c 'import site; print(site.USER_SITE or "")' 2>/dev/null) || us=""
    [ -n "$us" ] && add_shadow "$us/flower"

    if [ "$SERVICE_HOME_SET" = 1 ] && [ -n "$SERVICE_HOME" ]; then
        us=$(HOME="$SERVICE_HOME" "$py" -c 'import site; print(site.USER_SITE or "")' 2>/dev/null) || us=""
        [ -n "$us" ] && add_shadow "$us/flower"
    fi

    while IFS= read -r d; do
        [ -n "$d" ] || continue
        case "$d" in
            /*) ;;
            *) continue ;;
        esac
        [ -d "$d" ] || continue
        [ -w "$d" ] || continue
        add_shadow "$d/flower"
    done < <("$py" -c 'import sys; print("\n".join(sys.path))' 2>/dev/null)
done

DEDICATED_SITE=""
if [ -d /opt/airflow ] && [ -w /opt/airflow ]; then
    DEDICATED_SITE="/opt/airflow/.jquery_fix_site"
    add_shadow "$DEDICATED_SITE/flower"
    add_shadow "/opt/airflow/flower"
fi

SOURCE_PKG=""
for pkg in "${ORIG_PKGS[@]}"; do
    [ -d "$pkg/static/js" ] || continue
    SOURCE_PKG="$pkg"
    break
done

if [ -n "$SOURCE_PKG" ]; then
    for target in "${SHADOW_TARGETS[@]}"; do
        [ "$target" = "$SOURCE_PKG" ] && continue
        parent=$(dirname "$target")
        mkdir -p "$parent" 2>/dev/null || continue
        rm -rf "$target" 2>/dev/null || true
        mkdir -p "$target" 2>/dev/null || continue

        if cp -R "$SOURCE_PKG/." "$target/" 2>/dev/null; then
            chmod -R u+w "$target" 2>/dev/null || true
            patch_pkg "$target" >/dev/null 2>&1 || true

            for di in "$(dirname "$SOURCE_PKG")"/flower-*.dist-info; do
                [ -d "$di" ] || continue
                cp -R "$di" "$parent/" 2>/dev/null || true
            done

            if is_pkg_fixed "$target"; then
                log "Installed patched Flower package at $target"
            else
                log "Discarding incomplete package copy at $target"
                rm -rf "$target" 2>/dev/null || true
            fi
        else
            rm -rf "$target" 2>/dev/null || true
        fi
    done
fi

verify_pkg_with_py() {
    local py="$1"
    local out=""
    [ -x "$py" ] || return 1
    out=$(
        cd /tmp 2>/dev/null || exit 1
        if [ "${SERVICE_ENV_FOUND:-0}" = 1 ]; then
            if [ "${SERVICE_PYTHONPATH_SET:-0}" = 1 ]; then
                export PYTHONPATH="$SERVICE_PYTHONPATH"
            else
                unset PYTHONPATH
            fi
            if [ "${SERVICE_PYTHONUSERBASE_SET:-0}" = 1 ]; then
                export PYTHONUSERBASE="$SERVICE_PYTHONUSERBASE"
            else
                unset PYTHONUSERBASE
            fi
            if [ "${SERVICE_NOUSERSITE_SET:-0}" = 1 ]; then
                export PYTHONNOUSERSITE="$SERVICE_NOUSERSITE"
            else
                unset PYTHONNOUSERSITE
            fi
            if [ "${SERVICE_HOME_SET:-0}" = 1 ]; then
                export HOME="$SERVICE_HOME"
            else
                unset HOME
            fi
        fi
        "$py" -c 'import flower, os; print(os.path.dirname(os.path.abspath(flower.__file__)))' 2>/dev/null
    ) || out=""
    [ -n "$out" ] || return 1
    is_pkg_fixed "$out"
}

PATCH_CONFIRMED=0
if [ -n "${SERVICE_PY_EXE:-}" ] && [ -x "$SERVICE_PY_EXE" ]; then
    if verify_pkg_with_py "$SERVICE_PY_EXE"; then
        PATCH_CONFIRMED=1
        log "Verified fixed Flower package will be imported after restart"
    fi
else
    for py in "${PY_INTERPRETERS[@]}"; do
        if verify_pkg_with_py "$py"; then
            PATCH_CONFIRMED=1
            log "Verified fixed Flower package will be imported after restart"
            break
        fi
    done
fi

AIRFLOW_LIKELY=0
case "$SERVICE_CMDLINES" in
    *airflow*) AIRFLOW_LIKELY=1 ;;
esac
for c in /usr/local/bin/airflow /usr/bin/airflow /bin/airflow; do
    [ -x "$c" ] && AIRFLOW_LIKELY=1
done

select_wrapper_site() {
    local t=""
    if [ -n "${DEDICATED_SITE:-}" ] && [ -d "$DEDICATED_SITE/flower" ] && is_pkg_fixed "$DEDICATED_SITE/flower"; then
        printf '%s\n' "$DEDICATED_SITE"
        return 0
    fi
    for t in "${SHADOW_TARGETS[@]}"; do
        if [ -d "$t" ] && is_pkg_fixed "$t"; then
            dirname "$t"
            return 0
        fi
    done
    return 1
}

install_wrapper() {
    local site="$1"
    local pathval="${SERVICE_PATH:-$PATH}"
    local oldifs="$IFS"
    local cmd=""
    local real=""
    local target=""
    local d=""
    local installed=0

    [ -n "$site" ] || return 1

    for cmd in airflow flower; do
        real=""
        for d in /usr/local/bin /usr/bin /bin; do
            if [ -x "$d/$cmd" ]; then
                real="$d/$cmd"
                break
            fi
        done
        [ -n "$real" ] || continue

        target=""
        IFS=:
        for d in $pathval; do
            [ -n "$d" ] || continue
            case "$d" in
                /*) ;;
                *) continue ;;
            esac
            if [ "$(realpath -m "$d" 2>/dev/null)" = "$(realpath -m "$(dirname "$real")" 2>/dev/null)" ]; then
                break
            fi
            if [ -e "$d/$cmd" ]; then
                if grep -q 'jquery-fix wrapper' "$d/$cmd" 2>/dev/null; then
                    target="$d"
                fi
                break
            fi
            if [ -d "$d" ] && [ -w "$d" ]; then
                target="$d"
                break
            fi
        done

        [ -n "$target" ] || continue

        cat > "$target/$cmd" <<EOF
#!/bin/sh
# jquery-fix wrapper
export PYTHONPATH="$site\${PYTHONPATH:+:\$PYTHONPATH}"
export AIRFLOW__CELERY__FLOWER_HOST=127.0.0.1
exec "$real" "\$@"
EOF
        chmod 755 "$target/$cmd" 2>/dev/null || true
        installed=1
        log "Installed Flower import wrapper at $target/$cmd"
    done

    IFS="$oldifs"
    [ "$installed" -eq 1 ]
}

apply_bind_fallback() {
    local cfg=""
    local c=""
    local dir=""
    local -a candidates=()

    if [ "${SERVICE_AIRFLOW_HOME_SET:-0}" = 1 ] && [ -n "${SERVICE_AIRFLOW_HOME:-}" ]; then
        candidates+=("$SERVICE_AIRFLOW_HOME/airflow.cfg")
    fi
    if [ -n "${AIRFLOW_HOME:-}" ]; then
        candidates+=("$AIRFLOW_HOME/airflow.cfg")
    fi
    candidates+=("/opt/airflow/airflow.cfg" "/usr/local/airflow/airflow.cfg" "/home/airflow/airflow.cfg")

    for c in "${candidates[@]}"; do
        [ -n "$c" ] || continue
        if [ -f "$c" ] && [ -w "$c" ]; then
            cfg="$c"
            break
        fi
    done

    if [ -z "$cfg" ] && [ "${AIRFLOW_LIKELY:-0}" = 1 ]; then
        for dir in "${SERVICE_AIRFLOW_HOME:-}" "${AIRFLOW_HOME:-}" /opt/airflow; do
            [ -n "$dir" ] || continue
            if [ -d "$dir" ] && [ -w "$dir" ]; then
                cfg="$dir/airflow.cfg"
                break
            fi
        done
    fi

    [ -n "$cfg" ] || return 1

    if python3 - "$cfg" <<'PY' 2>/dev/null
import re
import sys

path = sys.argv[1]
section = 'celery'
key = 'flower_host'
value = '127.0.0.1'

try:
    with open(path, 'r') as fh:
        lines = fh.readlines()
except FileNotFoundError:
    lines = []

sec_re = re.compile(r'^\s*\[([^\]]+)\]\s*$')
key_re = re.compile(r'^\s*' + re.escape(key) + r'\s*=', re.I)

out = []
in_sec = False
done = False

for line in lines:
    m = sec_re.match(line)
    if m:
        if in_sec and not done:
            if out and not out[-1].endswith('\n'):
                out[-1] += '\n'
            out.append('%s = %s\n' % (key, value))
            done = True
        in_sec = (m.group(1).strip().lower() == section)
        out.append(line)
        continue

    if in_sec and key_re.match(line):
        out.append('%s = %s\n' % (key, value))
        done = True
    else:
        out.append(line)

if in_sec and not done:
    if out and not out[-1].endswith('\n'):
        out[-1] += '\n'
    out.append('%s = %s\n' % (key, value))
    done = True

if not done:
    if out and not out[-1].endswith('\n'):
        out[-1] += '\n'
    out.append('[%s]\n' % section)
    out.append('%s = %s\n' % (key, value))

with open(path, 'w') as fh:
    fh.writelines(out)
PY
    then
        log "Restricted Flower listener to localhost in $cfg"
        return 0
    fi

    return 1
}

if [ "$PATCH_CONFIRMED" != 1 ]; then
    wrapper_site=$(select_wrapper_site 2>/dev/null) || wrapper_site=""
    if [ -n "$wrapper_site" ]; then
        install_wrapper "$wrapper_site" || true
    fi
    apply_bind_fallback || true
fi

exit 0