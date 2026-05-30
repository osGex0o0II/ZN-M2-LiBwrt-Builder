#!/bin/sh
# ==========================================
# 首次开机初始化脚本
# ==========================================

# 1. 强制设置语言、主题、主机名
uci -q set luci.main.lang='zh_cn'
uci -q set luci.main.mediaurlbase='/luci-static/aurora'
uci -q set system.@system[0].hostname='ZN-M2'

# 2. 默认开启防火墙软件与硬件流量卸载 (NSS 核心)
uci -q set firewall.@defaults[0].flow_offloading='1'
uci -q set firewall.@defaults[0].flow_offloading_hw='1'

# 3. 保存并应用配置 (绝对不包含 network，保持默认 192.168.1.1)
uci commit luci
uci commit system
uci commit firewall

# 4. 重启防火墙确保 NSS 立即生效
/etc/init.d/firewall restart

exit 0
