#!/bin/sh

# 256M main router stability defaults. Keep the profile conservative: stable
# DNS entrypoint, no always-on web terminal, and low-frequency health checks.

uci -q set dhcp.@dnsmasq[0].noresolv='1'
uci -q set dhcp.@dnsmasq[0].localservice='1'
uci -q set dhcp.@dnsmasq[0].ednspacket_max='1232'
uci -q set dhcp.@dnsmasq[0].dnsforwardmax='150'

uci commit dhcp

# TTYD remains packaged for recovery, but stays off until manually enabled.
[ -x /etc/init.d/ttyd ] && /etc/init.d/ttyd disable 2>/dev/null || true
[ -x /etc/init.d/ttyd ] && /etc/init.d/ttyd stop 2>/dev/null || true

# The 256M build checks less frequently and uses a lower memory warning
# threshold to avoid creating background noise on a constrained device.
CRON_FILE="/etc/crontabs/root"
CRON_LINE="*/10 * * * * MIN_MEM_KB=16384 COOLDOWN_SEC=900 /usr/sbin/zn-m2-healthcheck >/dev/null 2>&1"
mkdir -p /etc/crontabs
touch "$CRON_FILE"
grep -Fxq "$CRON_LINE" "$CRON_FILE" 2>/dev/null || echo "$CRON_LINE" >> "$CRON_FILE"

[ -x /etc/init.d/cron ] && /etc/init.d/cron enable 2>/dev/null || true
[ -x /etc/init.d/cron ] && /etc/init.d/cron restart 2>/dev/null || true

exit 0
