#!/bin/sh

# DNS cache tuning for the 256M RAM factory model.
uci -q set dhcp.@dnsmasq[0].cachesize='4096'
uci -q set dhcp.@dnsmasq[0].min_cache_ttl='3600'
uci -q set dhcp.@dnsmasq[0].allservers='1'
uci -q commit dhcp

# File descriptor limits for router workloads. Keep this idempotent because
# uci-defaults scripts can be retried if any earlier command fails.
mkdir -p /etc/security
touch /etc/security/limits.conf
grep -qF '* soft nofile 8192' /etc/security/limits.conf || echo '* soft nofile 8192' >> /etc/security/limits.conf
grep -qF '* hard nofile 8192' /etc/security/limits.conf || echo '* hard nofile 8192' >> /etc/security/limits.conf

# 上游公共 DNS。
uci -q del dhcp.@dnsmasq[0].server
uci -q add_list dhcp.@dnsmasq[0].server='223.5.5.5'
uci -q add_list dhcp.@dnsmasq[0].server='119.29.29.29'
uci commit dhcp

# Conntrack limit ? cap at 16K to save ~15MB peak RAM on 160MB device.
echo 16384 > /proc/sys/net/netfilter/nf_conntrack_max

exit 0

