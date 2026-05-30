#!/bin/sh
# ==========================================
# 首次开机初始化脚本 (执行一次后自动销毁)
# ==========================================

# 1. 强制设置语言、主题、主机名
uci set luci.main.lang='zh_cn'
uci set luci.main.mediaurlbase='/luci-static/aurora'
uci set system.@system[0].hostname='ZN-M2'

# 2. 默认开启防火墙软件与硬件流量卸载 (NSS 核心)
uci set firewall.@defaults[0].flow_offloading='1'
uci set firewall.@defaults[0].flow_offloading_hw='1'

# 3. 修改默认 LAN 口 IP 地址为 10.0.5.1
uci set network.lan.ipaddr='10.0.5.1'

# 4. 保存并应用所有配置
uci commit luci
uci commit system
uci commit firewall
uci commit network

exit 0
