#!/bin/sh

# 1G proxy gateway stability defaults. Keep diagnostics available, but avoid
# exposing remote shells or doing broad restarts by default.

# DNS entrypoint hardening: LAN clients use dnsmasq as the local resolver, while
# upstream selection stays explicit instead of inheriting WAN-provided DNS.
uci -q set dhcp.@dnsmasq[0].noresolv='1'
uci -q set dhcp.@dnsmasq[0].localservice='1'
uci -q set dhcp.@dnsmasq[0].ednspacket_max='1232'
uci -q set dhcp.@dnsmasq[0].dnsforwardmax='300'

# Slightly larger ring buffer for proxy-gateway troubleshooting on the 1G build.
uci -q set system.@system[0].log_size='128'

uci commit dhcp
uci commit system

# TTYD remains installed for recovery and LuCI use, but does not run until the
# administrator starts it.
[ -x /etc/init.d/ttyd ] && /etc/init.d/ttyd disable 2>/dev/null || true
[ -x /etc/init.d/ttyd ] && /etc/init.d/ttyd stop 2>/dev/null || true

# Run lightweight health checks every five minutes. The checker restarts only
# dnsmasq or HomeProxy, and includes its own cooldown to avoid restart loops.
CRON_FILE="/etc/crontabs/root"
CRON_LINE="*/5 * * * * /usr/sbin/zn-m2-healthcheck >/dev/null 2>&1"
mkdir -p /etc/crontabs
touch "$CRON_FILE"
grep -Fxq "$CRON_LINE" "$CRON_FILE" 2>/dev/null || echo "$CRON_LINE" >> "$CRON_FILE"

[ -x /etc/init.d/cron ] && /etc/init.d/cron enable 2>/dev/null || true
[ -x /etc/init.d/cron ] && /etc/init.d/cron restart 2>/dev/null || true

exit 0
