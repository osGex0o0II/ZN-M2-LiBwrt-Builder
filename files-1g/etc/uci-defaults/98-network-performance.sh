#!/bin/sh

# These are factory defaults, not upgrade migrations. During a config-preserving
# sysupgrade the restored archive remains present until /etc/init.d/done (S95).
if [ "${ZN_M2_CONFIG_RESTORED:-0}" = "1" ] ||
   [ -f /sysupgrade.tgz ] || [ -f /tmp/sysupgrade.tar ]; then
	echo "Preserved configuration detected; skip network performance defaults"
	exit 0
fi

# DNS cache tuning — 1G 版本（代理网关场景）。
# cachesize=10000: 1GB RAM 下分配更多内存给 DNS 缓存，减少上游查询延迟
# Preserve authoritative TTLs so dynamic proxy/CDN endpoints can refresh on time.
# allservers=1: 并发查询所有上游 DNS 服务器，取最快响应
uci -q set dhcp.@dnsmasq[0].cachesize='10000'
uci -q delete dhcp.@dnsmasq[0].min_cache_ttl
uci -q set dhcp.@dnsmasq[0].allservers='1'
uci -q commit dhcp

# 上游公共 DNS。
uci -q del dhcp.@dnsmasq[0].server
uci -q add_list dhcp.@dnsmasq[0].server='223.5.5.5'
uci -q add_list dhcp.@dnsmasq[0].server='119.29.29.29'
uci commit dhcp

exit 0
