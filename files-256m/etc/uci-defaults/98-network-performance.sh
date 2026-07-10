#!/bin/sh

# Do not replace administrator DNS settings after a config-preserving upgrade.
if [ "${ZN_M2_CONFIG_RESTORED:-0}" = "1" ] ||
   [ -f /sysupgrade.tgz ] || [ -f /tmp/sysupgrade.tar ]; then
	echo "Preserved configuration detected; skip 256M network defaults"
	exit 0
fi

# DNS cache tuning for the 256M main-router profile. Respect authoritative TTLs
# and let dnsmasq choose a healthy WAN-provided resolver instead of duplicating
# every query to hard-coded public services.
uci -q set dhcp.@dnsmasq[0].cachesize='4096'
uci -q delete dhcp.@dnsmasq[0].min_cache_ttl
uci -q delete dhcp.@dnsmasq[0].allservers
uci -q delete dhcp.@dnsmasq[0].server
uci commit dhcp

exit 0
