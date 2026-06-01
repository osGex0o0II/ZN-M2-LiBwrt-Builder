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

/etc/init.d/firewall restart || true
/etc/init.d/miniupnpd enable 2>/dev/null || true

exit 0
