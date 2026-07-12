#!/bin/sh

if [ "${ZN_M2_CONFIG_RESTORED:-0}" != "1" ] &&
   [ ! -f /sysupgrade.tgz ] && [ ! -f /tmp/sysupgrade.tar ]; then
	exit 0
fi

noresolv="$(uci -q get dhcp.@dnsmasq[0].noresolv 2>/dev/null || true)"
servers="$(uci -q get dhcp.@dnsmasq[0].server 2>/dev/null || true)"
[ "$noresolv" = "1" ] || exit 0

case "$servers" in
	'223.5.5.5 119.29.29.29'|'119.29.29.29 223.5.5.5') ;;
	*) exit 0 ;;
esac

uci -q set dhcp.@dnsmasq[0].noresolv='0'
uci -q set dhcp.@dnsmasq[0].localservice='1'
uci -q set dhcp.@dnsmasq[0].ednspacket_max='1232'
uci -q set dhcp.@dnsmasq[0].dnsforwardmax='150'
uci -q set dhcp.@dnsmasq[0].cachesize='4096'
uci -q delete dhcp.@dnsmasq[0].server
uci -q delete dhcp.@dnsmasq[0].min_cache_ttl
uci -q delete dhcp.@dnsmasq[0].allservers
uci -q commit dhcp
logger -t zn-m2-upgrade "migrated legacy fixed DNS policy to WAN-provided resolvers" 2>/dev/null || true

exit 0
