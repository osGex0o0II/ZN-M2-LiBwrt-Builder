#!/bin/sh

# DNS cache tuning — 1G 版本（代理网关场景）。
# cachesize=10000: 1GB RAM 下分配更多内存给 DNS 缓存，减少上游查询延迟
# min_cache_ttl=600: 较低 TTL 确保代理节点切换时的 DNS 记录及时刷新
# allservers=1: 并发查询所有上游 DNS 服务器，取最快响应
uci -q set dhcp.@dnsmasq[0].cachesize='10000'
uci -q set dhcp.@dnsmasq[0].min_cache_ttl='600'
uci -q set dhcp.@dnsmasq[0].allservers='1'
uci -q commit dhcp

uci commit dhcp

# 上游公共 DNS。
uci -q del dhcp.@dnsmasq[0].server
uci -q add_list dhcp.@dnsmasq[0].server='223.5.5.5'
uci -q add_list dhcp.@dnsmasq[0].server='119.29.29.29'
uci commit dhcp

exit 0
