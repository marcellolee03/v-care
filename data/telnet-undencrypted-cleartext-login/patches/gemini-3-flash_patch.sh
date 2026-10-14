```bash
#!/bin/bash
set -euo pipefail

# Ensure the script is run with root privileges
[[ "$(id -u)" -eq 0 ]] || exit 1

# 1. Disable and mask systemd-managed telnet sockets/services
# Standard Debian telnetd uses telnet.socket
for unit in telnet.socket telnet.service; do
    if systemctl list-unit-files | grep -q "^${unit}" 2>/dev/null; then
        systemctl disable --now "$unit" >/dev/null 2>&1 || true
        systemctl mask "$unit" >/dev/null 2>&1 || true
    fi
done

# 2. Mitigate inetd-managed Telnet (including port 2323)
if [[ -f /etc/inetd.conf ]]; then
    # Comment out lines starting with 'telnet' or the specific port '2323'
    /bin/sed -i '/^[[:space:]]*\(telnet\|2323\)/ s/^[[:space:]]*/# /' /etc/inetd.conf
    systemctl reload inetd >/dev/null 2>&1 || true
fi

# 3. Mitigate xinetd-managed Telnet
if [[ -d /etc/xinetd.d ]]; then
    found_xinetd=0
    for f in /etc/xinetd.d/*; do
        if [[ -f "$f" ]] && grep -qiE "telnet|port.*=.*2323" "$f"; then
            # Remove existing disable lines and inject 'disable = yes' idempotently
            /bin/sed -i '/disable[[:space:]]*=/d; /{/a \    disable = yes' "$f"
            found_xinetd=1
        fi
    done
    [[ $found_xinetd -eq 1 ]] && systemctl reload xinetd >/dev/null 2>&1 || true
fi

# 4. Terminate active telnetd processes to clear current unencrypted sessions
# Uses awk to identify PIDs of running telnet daemons
pids=$(ps -eo pid,comm | /usr/bin/awk '$2 ~ /telnetd/ {print $1}')
if [[ -n "$pids" ]]; then
    echo "$pids" | xargs kill -9 >/dev/null 2>&1 || true
fi

exit 0
```