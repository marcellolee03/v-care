#!/usr/bin/env bash
set -u

export LC_ALL=C
export LANG=C
export DEBIAN_FRONTEND=noninteractive

GF_HOME="${GF_HOME:-/usr/local/glassfish4}"
DNAME='CN=localhost,OU=GlassFish,O=Oracle Corporation,L=Santa Clara,ST=California,C=US'
VALIDITY_DAYS=3650
TARGET_SERIAL='31EB8D9F'
TARGET_SHA256='08DEFEE67D8B168E29B80A97E5233C8BE32B316ED389AACE05BE31DAA702036B'

find_keytool() {
  local k
  if command -v keytool >/dev/null 2>&1; then
    command -v keytool
    return 0
  fi
  for k in \
    /usr/local/openjdk-8/bin/keytool \
    /usr/local/openjdk-8/jre/bin/keytool \
    "$GF_HOME/../openjdk-8/bin/keytool" \
    /usr/lib/jvm/*/bin/keytool; do
    if [ -x "$k" ]; then
      printf '%s\n' "$k"
      return 0
    fi
  done
  return 1
}

KEYTOOL_BIN="$(find_keytool)" || {
  echo "ERROR: keytool is not available; cannot replace the GlassFish certificate." >&2
  exit 1
}

kt() {
  "$KEYTOOL_BIN" -J-Duser.language=en -J-Duser.country=US "$@"
}

collect_password_candidates() {
  local cfg="$1"
  {
    printf '%s\n' changeit adminadmin glassfish password secret master ''
    if [ -f "$cfg" ]; then
      grep -oE 'javax\.net\.ssl\.keyStorePassword=[^<" ]+' "$cfg" 2>/dev/null | sed 's/^[^=]*=//'
      grep -oE 'javax\.net\.ssl\.trustStorePassword=[^<" ]+' "$cfg" 2>/dev/null | sed 's/^[^=]*=//'
      grep -oE '(key-store-password|keystore-password|keyStorePassword)="[^"]*"' "$cfg" 2>/dev/null | sed 's/.*="//;s/"$//'
      grep -oE '(key-store-password|keystore-password|keyStorePassword)[[:space:]]*=[[:space:]]*[^ <"]+' "$cfg" 2>/dev/null | sed 's/.*=[[:space:]]*//'
      grep -oE 'name="(key-store-password|keystore-password|keyStorePassword)"[^>]*value="[^"]*"' "$cfg" 2>/dev/null | sed 's/.*value="//;s/"$//'
      grep -oE '\$\{[^}]*=[^}]*\}' "$cfg" 2>/dev/null | sed 's/.*=//'
    fi
  } | tr -d '\r' | sed -e 's/^"//' -e "s/^'//" -e 's/"$//' -e "s/'$//" | awk '!seen[$0]++'
}

select_password() {
  local ks="$1" cfg="$2" p
  while IFS= read -r p; do
    if kt -list -keystore "$ks" -storepass "$p" >/dev/null 2>&1; then
      printf '%s\n' "$p"
      return 0
    fi
  done < <(collect_password_candidates "$cfg")
  return 1
}

get_aliases() {
  kt -list -v -keystore "$1" -storepass "$2" 2>/dev/null \
    | tr -d '\r' \
    | sed -n 's/^Alias name: //p'
}

is_private_entry() {
  kt -list -v -alias "$3" -keystore "$1" -storepass "$2" 2>/dev/null \
    | tr -d '\r' \
    | grep -Eq '^Entry type: (PrivateKeyEntry|keyEntry)'
}

cert_is_expired() {
  if kt -exportcert -rfc -alias "$3" -keystore "$1" -storepass "$2" 2>/dev/null \
       | openssl x509 -noout -checkend 0 >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

cert_matches_target() {
  local detail
  detail="$(kt -list -v -alias "$3" -keystore "$1" -storepass "$2" 2>/dev/null | tr -d '\r')"
  [ -n "$detail" ] || return 1
  if printf '%s\n' "$detail" | grep -qi "Serial number:.*$TARGET_SERIAL"; then
    return 0
  fi
  if printf '%s\n' "$detail" | tr -d ':' | grep -qi "$TARGET_SHA256"; then
    return 0
  fi
  return 1
}

preserve_metadata() {
  local ref="$1" dest="$2"
  [ -f "$ref" ] || return 0
  chmod --reference="$ref" "$dest" 2>/dev/null || true
  chown --reference="$ref" "$dest" 2>/dev/null || true
}

regenerate_alias() {
  local ks="$1" pass="$2" alias="$3" kstype="$4"
  local type_args=()
  [ -n "$kstype" ] && type_args=(-storetype "$kstype")

  kt -delete -alias "$alias" -keystore "$ks" -storepass "$pass" >/dev/null 2>&1 || true

  if kt -genkeypair \
      -alias "$alias" \
      -keyalg RSA \
      -keysize 2048 \
      -sigalg SHA256withRSA \
      -validity "$VALIDITY_DAYS" \
      -dname "$DNAME" \
      -ext "SAN=DNS:localhost,IP:127.0.0.1" \
      -keystore "$ks" \
      -storepass "$pass" \
      -keypass "$pass" \
      "${type_args[@]}" >/dev/null 2>&1; then
    return 0
  fi

  kt -delete -alias "$alias" -keystore "$ks" -storepass "$pass" >/dev/null 2>&1 || true

  if kt -genkeypair \
      -alias "$alias" \
      -keyalg RSA \
      -keysize 2048 \
      -validity "$VALIDITY_DAYS" \
      -dname "$DNAME" \
      -keystore "$ks" \
      -storepass "$pass" \
      -keypass "$pass" \
      "${type_args[@]}" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

update_truststore() {
  local ks="$1" pass="$2" alias="$3"
  local cfg ts tpass ttype tstype tmp tstore_args backup
  cfg="$(dirname "$ks")/domain.xml"
  ts="$(dirname "$ks")/cacerts.jks"
  [ "$ts" = "$ks" ] && return 0
  [ -f "$ts" ] || return 0

  tpass="$(select_password "$ts" "$cfg")" || return 0

  ttype="$(kt -list -v -alias "$alias" -keystore "$ts" -storepass "$tpass" 2>/dev/null \
    | tr -d '\r' | sed -n 's/^Entry type: //p' | head -n1)"
  [ "$ttype" = "PrivateKeyEntry" ] && return 0

  tstype="$(kt -list -keystore "$ts" -storepass "$tpass" 2>/dev/null \
    | tr -d '\r' | sed -n 's/^Keystore type: //p' | head -n1)"
  tstore_args=()
  [ -n "$tstype" ] && tstore_args=(-storetype "$tstype")

  tmp="$(mktemp /tmp/glassfish-cert.XXXXXX 2>/dev/null)" || return 0
  if ! kt -exportcert -rfc -alias "$alias" -keystore "$ks" -storepass "$pass" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    return 0
  fi

  backup="${ts}.bak.$(date +%Y%m%d%H%M%S).$$"
  cp -p "$ts" "$backup" 2>/dev/null || true

  kt -delete -alias "$alias" -keystore "$ts" -storepass "$tpass" >/dev/null 2>&1 || true
  if kt -importcert -noprompt -alias "$alias" -file "$tmp" -keystore "$ts" -storepass "$tpass" "${tstore_args[@]}" >/dev/null 2>&1; then
    preserve_metadata "$backup" "$ts"
  else
    if [ -f "$backup" ]; then
      cp -p "$backup" "$ts" 2>/dev/null || true
      preserve_metadata "$backup" "$ts"
    fi
  fi

  rm -f "$tmp"
}

domain_root="$GF_HOME/glassfish/domains"
if [ ! -d "$domain_root" ]; then
  for root in /usr/local/glassfish*/glassfish/domains /opt/glassfish*/glassfish/domains; do
    if [ -d "$root" ]; then
      domain_root="$root"
      break
    fi
  done
fi

found_keystore=0
updated=0

while IFS= read -r ks; do
  [ -f "$ks" ] || continue
  found_keystore=1
  cfg="$(dirname "$ks")/domain.xml"

  if ! pass="$(select_password "$ks" "$cfg")"; then
    echo "WARNING: unable to open $ks with a known password; skipping." >&2
    continue
  fi

  kstype="$(kt -list -keystore "$ks" -storepass "$pass" 2>/dev/null \
    | tr -d '\r' | sed -n 's/^Keystore type: //p' | head -n1)"

  backup="${ks}.bak.$(date +%Y%m%d%H%M%S).$$"
  if ! cp -p "$ks" "$backup" 2>/dev/null; then
    echo "WARNING: unable to back up $ks; skipping." >&2
    continue
  fi

  changed_this=0
  while IFS= read -r alias; do
    [ -n "$alias" ] || continue
    is_private_entry "$ks" "$pass" "$alias" || continue

    if cert_matches_target "$ks" "$pass" "$alias" || cert_is_expired "$ks" "$pass" "$alias"; then
      echo "Replacing SSL certificate alias '$alias' in $ks"
      if regenerate_alias "$ks" "$pass" "$alias" "$kstype" \
         && kt -list -alias "$alias" -keystore "$ks" -storepass "$pass" >/dev/null 2>&1 \
         && ! cert_is_expired "$ks" "$pass" "$alias"; then
        changed_this=1
        updated=1
        update_truststore "$ks" "$pass" "$alias"
      else
        echo "ERROR: failed to replace alias '$alias' in $ks; restoring original keystore." >&2
        cp -p "$backup" "$ks" 2>/dev/null || true
        preserve_metadata "$backup" "$ks"
        changed_this=0
        break
      fi
    fi
  done < <(get_aliases "$ks" "$pass")

  if [ "$changed_this" -eq 1 ]; then
    preserve_metadata "$backup" "$ks"
    echo "Updated GlassFish keystore: $ks"
  else
    rm -f "$backup" 2>/dev/null || true
  fi
done < <(find "$domain_root" -type f \( -name '*.jks' -o -name '*.JKS' -o -name '*.p12' -o -name '*.P12' -o -name '*.pfx' -o -name '*.PFX' -o -name 'keystore' \) 2>/dev/null | sort)

if [ "$found_keystore" -eq 0 ]; then
  echo "WARNING: no GlassFish JKS/PKCS12 keystore was found under $domain_root." >&2
elif [ "$updated" -eq 0 ]; then
  echo "WARNING: no expired GlassFish certificate was found to replace." >&2
else
  echo "GlassFish certificate remediation complete. Restart the container to load the new certificate."
fi

exit 0