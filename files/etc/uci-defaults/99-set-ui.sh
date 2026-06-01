#!/bin/sh

# Language, theme, and hostname.
uci -q set luci.main.lang='zh_cn'
uci -q set luci.main.mediaurlbase='/luci-static/aurora'
uci -q set system.@system[0].hostname='ZN-M2'

# Firewall software and hardware flow offload.
uci -q set firewall.@defaults[0].flow_offloading='1'
uci -q set firewall.@defaults[0].flow_offloading_hw='1'

uci commit luci
uci commit system
uci commit firewall

# UPnP 默认开启。
uci -q set upnpd.config.enabled='1'
uci commit upnpd

# 流量统计默认采集 LAN 网桥。
uci -q set luci_statistics.collectd_interface.Interface='br-lan'
uci commit luci_statistics

# WAN 口默认 DHCP 客户端（即插即用）。
uci -q set network.wan.proto='dhcp'
uci -q set network.wan6.proto='dhcpv6'

# WAN SSH 加固：dropbear 仅监听 LAN 接口。
uci -q set dropbear.@dropbear[0].Interface='lan'

# 删除 WAN 的 ICMP ping 放行规则（按特征匹配，不依赖规则名称）。
idx=0
while uci -q get firewall.@rule[$idx] >/dev/null 2>&1; do
  src="$(uci -q get firewall.@rule[$idx].src 2>/dev/null || true)"
  proto="$(uci -q get firewall.@rule[$idx].proto 2>/dev/null || true)"
  target="$(uci -q get firewall.@rule[$idx].target 2>/dev/null || true)"
  if [ "$src" = "wan" ] && [ "$proto" = "icmp" ] && [ "$target" = "ACCEPT" ]; then
    uci -q delete firewall.@rule[$idx]
    break
  fi
  idx=$((idx + 1))
done

# FullCone NAT 开启（fw3 生效，fw4 静默忽略，无副作用）。
uci -q set firewall.@defaults[0].fullcone='1'

# LuCI 仪表盘显示 CPU 负载和内存信息。
uci -q set luci.main.show_load='1'
uci -q set luci.main.sa_memory='1'

# DNS 防劫持保护。
uci -q set dhcp.@dnsmasq[0].rebind_protection='1'
uci -q set dhcp.@dnsmasq[0].rebind_localhost='1'

# 系统日志上限 64KB。
uci -q set system.@system[0].log_size='64'

uci commit network
uci commit dropbear
uci commit firewall
uci commit luci
uci commit dhcp
uci commit system

/etc/init.d/firewall restart || true
/etc/init.d/miniupnpd enable 2>/dev/null && /etc/init.d/miniupnpd start 2>/dev/null || true

exit 0
