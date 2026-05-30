#!/bin/sh
# ==========================================
# 首次开机执行：DNS极限调优与系统资源解锁
# ==========================================

# 1. 解锁 dnsmasq 极限性能
# 将 DNS 缓存拉大到 10000 条，并强制最小 TTL 为 1 小时，大幅减少重复查询
uci set dhcp.@dnsmasq[0].cachesize='10000'
uci set dhcp.@dnsmasq[0].min_cache_ttl='3600'
# 开启并发查询：同时向所有上游 DNS 发送请求，谁先回来用谁，极致降低解析延迟
uci set dhcp.@dnsmasq[0].allservers='1'
uci commit dhcp

# 2. 提升系统级文件描述符上限
# 防止跑 HomeProxy 代理或高并发 BT 时出现 "Too many open files" 报错
echo "* soft nofile 65535" >> /etc/security/limits.conf
echo "* hard nofile 65535" >> /etc/security/limits.conf

exit 0
