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

/etc/init.d/firewall restart || true

exit 0
