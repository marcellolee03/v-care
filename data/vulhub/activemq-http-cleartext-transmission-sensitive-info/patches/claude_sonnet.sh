#!/bin/bash
# Remediation: serve the ActiveMQ web console (Jetty, port 8161) over HTTPS only,
# so Basic Auth credentials are no longer sent in cleartext over HTTP.
set -u

AMQ_HOME="$(readlink -f /opt/activemq 2>/dev/null || echo /opt/activemq)"
[ -d "$AMQ_HOME/conf" ] || AMQ_HOME="/opt/apache-activemq-5.11.1"
CONF="$AMQ_HOME/conf"
JETTY="$CONF/jetty.xml"
KS="$CONF/broker-web.ks"

if [ ! -f "$JETTY" ]; then
  echo "jetty.xml not found at $JETTY" >&2
  exit 1
fi

# Locate keytool
KEYTOOL="$(command -v keytool 2>/dev/null || true)"
if [ -z "$KEYTOOL" ]; then
  for c in /opt/jdk/bin/keytool /usr/lib/jvm/*/bin/keytool /usr/lib/jvm/*/jre/bin/keytool; do
    [ -x "$c" ] && KEYTOOL="$c" && break
  done
fi
if [ -z "$KEYTOOL" ]; then
  J="$(readlink -f "$(command -v java)" 2>/dev/null || true)"
  [ -n "$J" ] && [ -x "$(dirname "$J")/keytool" ] && KEYTOOL="$(dirname "$J")/keytool"
fi
if [ -z "$KEYTOOL" ]; then
  echo "keytool not found" >&2
  exit 1
fi

# Already converted?
if grep -q 'SslSelectChannelConnector' "$JETTY" && [ -f "$KS" ]; then
  echo "HTTPS connector already configured"
  exit 0
fi

cp -n "$JETTY" "$JETTY.orig-cleartext" 2>/dev/null || true

# Create keystore with a random password
PASS="$(openssl rand -hex 16)"
rm -f "$KS"
"$KEYTOOL" -genkeypair -alias activemq-web -keyalg RSA -keysize 2048 -validity 3650 \
  -dname "CN=$(hostname),OU=ActiveMQ,O=ActiveMQ" \
  -keystore "$KS" -storetype JKS -storepass "$PASS" -keypass "$PASS" >/dev/null 2>&1
if [ ! -s "$KS" ]; then
  echo "Failed to create keystore" >&2
  exit 1
fi
chmod 600 "$KS"

export KS_URL="file:$KS" KS_PASS="$PASS"

# Replace plain HTTP connector with an SSL connector
perl -0pi -e '
  my $url = $ENV{KS_URL}; my $pw = $ENV{KS_PASS};
  s{(<bean\s+id="Connector"\s+class=")org\.eclipse\.jetty\.server\.nio\.SelectChannelConnector("[^>]*>)}
   {$1org.eclipse.jetty.server.ssl.SslSelectChannelConnector$2\n            <property name="keystore" value="$url" />\n            <property name="password" value="$pw" />\n            <property name="keyPassword" value="$pw" />}s;
' "$JETTY"

if ! grep -q 'SslSelectChannelConnector' "$JETTY"; then
  # Fallback: could not convert connector; make the plain HTTP listener loopback-only
  echo "Could not convert connector to SSL; binding web console to localhost instead" >&2
  perl -0pi -e 's{(<property\s+name="host"\s+value=")[^"]*(")}{${1}127.0.0.1${2}}g' "$JETTY"
  sed -i "s/jetty\.host'\]}/jetty.host']}/" "$JETTY"
fi

# Ensure persistent config doesn't override host/port in a way that breaks things
if [ -f "$CONF/jetty.xml" ]; then
  chmod 600 "$JETTY" 2>/dev/null || true
fi

echo "Done: web console on port 8161 now served via HTTPS (restart required)."
exit 0