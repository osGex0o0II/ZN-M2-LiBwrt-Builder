#!/bin/sh

# Language, theme, and hostname.
uci -q set luci.main.lang='zh_cn'
uci -q set luci.main.mediaurlbase='/luci-static/aurora'
uci -q set system.@system[0].hostname='ZN-M2'

# Firewall offloading: 默认关闭以兼容 NSS 硬件加速。
# NSS（Network Subsystem）在 IPQ60xx 上接管 NAT/路由数据面处理。
# OpenWrt 软件 flow offloading（nftables flowtable）与 NSS 存在以下冲突：
#   1. 两者竞争数据包处理路径，导致冗余处理及错误
#   2. 硬件卸载被软件 offloading 打断，无法发挥 NSS 性能
#   3. 极端情况下出现节点黑洞（qosmio/openwrt-ipq 已确认）
# 参考：qosmio/openwrt-ipq#nss-warning
# 如需启用，请通过 LuCI -> 防火墙 -> 流量分载 手动打开。
# 注意：NSS 与 flow offloading 不兼容（qosmio 明确警告），开启后可能
# 导致数据路径冲突、性能下降甚至节点黑洞。不建议在生产环境中启用。
uci -q set firewall.@defaults[0].flow_offloading='0'
uci -q set firewall.@defaults[0].flow_offloading_hw='0'

# UPnP is available in LuCI, but stays off until WAN is ready.
uci -q set upnpd.config.enabled='0'
uci -q set upnpd.config.external_iface='wan'
uci -q set upnpd.config.internal_iface='lan'

# WAN 口默认 DHCP 客户端（即插即用）。
uci -q set network.wan.proto='dhcp'
uci -q set network.wan6.proto='dhcpv6'
uci -q set network.wan6.reqprefix='auto'

# WAN SSH 加固：dropbear 仅监听 LAN 接口。
uci -q set dropbear.@dropbear[0].DirectInterface='lan'
uci -q set dropbear.@dropbear[0]._direct='1'
uci -q delete dropbear.@dropbear[0].Interface

# 删除 WAN 的 ICMP ping 放行规则（按特征匹配，不依赖规则名称）。
# 删除后索引不递增（uci delete 后索引自动前移）。
idx=0
while uci -q get firewall.@rule[$idx] >/dev/null 2>&1; do
  src="$(uci -q get firewall.@rule[$idx].src 2>/dev/null || true)"
  proto="$(uci -q get firewall.@rule[$idx].proto 2>/dev/null || true)"
  target="$(uci -q get firewall.@rule[$idx].target 2>/dev/null || true)"
  if [ "$src" = "wan" ] && [ "$proto" = "icmp" ] && [ "$target" = "ACCEPT" ]; then
    uci -q delete firewall.@rule[$idx]
  else
    idx=$((idx + 1))
  fi
done

# LuCI 仪表盘显示 CPU 负载和内存信息。
uci -q set luci.main.show_load='1'
uci -q set luci.main.sa_memory='1'

# DNS 防劫持保护。
uci -q set dhcp.@dnsmasq[0].rebind_protection='1'
uci -q set dhcp.@dnsmasq[0].rebind_localhost='1'

# 系统日志上限 64KB。
uci -q set system.@system[0].log_size='64'

# Keep ZeroTier packaged for LuCI, but do not run it until a network is
# configured. The init hook otherwise logs missing-port notices during boot.
uci -q set zerotier.global.enabled='0'

uci commit luci
uci commit system
uci commit firewall
uci commit upnpd
uci commit network
uci commit dropbear
uci commit dhcp
uci commit zerotier

/etc/init.d/firewall restart || true
[ -x /etc/init.d/miniupnpd ] && /etc/init.d/miniupnpd disable 2>/dev/null || true
[ -x /etc/init.d/miniupnpd ] && /etc/init.d/miniupnpd stop 2>/dev/null || true
[ -x /etc/init.d/zerotier ] && /etc/init.d/zerotier disable 2>/dev/null || true
[ -x /etc/init.d/zerotier ] && /etc/init.d/zerotier stop 2>/dev/null || true

exit 0
