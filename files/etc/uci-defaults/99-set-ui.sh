#!/bin/sh

BOARD_NAME="${ZN_M2_BOARD_NAME:-$(cat /tmp/sysinfo/board_name 2>/dev/null || echo unknown)}"
if [ "$BOARD_NAME" = "zn,m2" ]; then
  # Wi-Fi is disabled in these wired-only images. Remove wireless LED sections
  # that may be preserved from earlier sysupgrade overlays.
  uci -q delete system.led_wlan2g
  uci -q delete system.led_wlan5g
  # board_detect sources every file in /etc/board.d, so builder backups must
  # not remain there on upgraded devices.
  rm -f /etc/board.d/01_leds.*.bak /etc/board.d/01_leds.wifi.bak 2>/dev/null || true

  # Regenerate stale board metadata if it still contains old phy*-ap0 LED
  # bindings, but only after the firmware board.d source is known to be clean.
  if [ -s /etc/board.json ] && grep -q 'phy[01]-ap0' /etc/board.json; then
    if [ -f /etc/board.d/01_leds ] && ! sed -n '/zn,m2)/,/;;/p' /etc/board.d/01_leds | grep -q 'phy[01]-ap0'; then
      rm -f /etc/board.json
      /bin/board_detect /etc/board.json 2>/dev/null || true
    fi
  fi
fi

# Everything below defines fresh-image defaults. OpenWrt keeps the restored
# archive until S95, after uci-defaults run at S10. The hardware cleanup above
# is an upgrade migration, but administrator policy below must be preserved.
if [ "${ZN_M2_CONFIG_RESTORED:-0}" = "1" ] ||
   [ -f /sysupgrade.tgz ] || [ -f /tmp/sysupgrade.tar ]; then
  [ "$BOARD_NAME" = "zn,m2" ] && uci commit system
	echo "Preserved configuration detected; applied hardware migration only"
	exit 0
fi

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

# Keep full-cone NAT available for manual gaming/P2P use, but default to the
# conservative masquerade path for a stable main-router profile.
uci -q set firewall.@defaults[0].fullcone='0'
uci -q set firewall.@defaults[0].fullcone6='0'

if [ -x /etc/init.d/miniupnpd ]; then
  # UPnP is available in LuCI, but stays off until WAN is ready.
  uci -q set upnpd.config.enabled='0'
  uci -q set upnpd.config.external_iface='wan'
  uci -q set upnpd.config.internal_iface='lan'
fi

# WAN 口默认 DHCP 客户端（即插即用）。
uci -q set network.wan.proto='dhcp'
uci -q set network.wan6.proto='dhcpv6'
uci -q set network.wan6.reqprefix='auto'

# WAN SSH 加固：dropbear 仅监听 LAN 接口。
uci -q set dropbear.@dropbear[0].DirectInterface='lan'
uci -q set dropbear.@dropbear[0]._direct='1'
uci -q delete dropbear.@dropbear[0].Interface

# Remove only the stock IPv4 echo-request rule. `uci -X show` exposes stable
# cfg section IDs, avoiding anonymous @rule index movement during deletion.
uci -X show firewall 2>/dev/null | sed -n "s/^firewall\.\(cfg[0-9a-f]*\)\.src='wan'$/\1/p" | while read -r section; do
  proto="$(uci -q get "firewall.${section}.proto" 2>/dev/null || true)"
  target="$(uci -q get "firewall.${section}.target" 2>/dev/null || true)"
  family="$(uci -q get "firewall.${section}.family" 2>/dev/null || true)"
  icmp_types="$(uci -q get "firewall.${section}.icmp_type" 2>/dev/null || true)"
  [ "$proto" = "icmp" ] || continue
  [ "$target" = "ACCEPT" ] || continue
  [ "$family" = "ipv4" ] || continue
  case " ${icmp_types} " in
    *" echo-request "*)
      uci -q delete "firewall.${section}"
      echo "Deleted WAN IPv4 echo-request rule: firewall.${section}"
      ;;
  esac
done

# LuCI 仪表盘显示 CPU 负载和内存信息。
uci -q set luci.main.show_load='1'
uci -q set luci.main.sa_memory='1'

# DNS 防劫持保护。
uci -q set dhcp.@dnsmasq[0].rebind_protection='1'
uci -q set dhcp.@dnsmasq[0].rebind_localhost='1'

# 系统日志上限 64KB。
uci -q set system.@system[0].log_size='64'
# Keep routine cron executions out of logread; actual job output still logs.
uci -q set system.@system[0].cronloglevel='9'

if [ -x /etc/init.d/zerotier ]; then
  # Keep ZeroTier packaged for LuCI, but do not run it until a network is
  # configured. The init hook otherwise logs missing-port notices during boot.
  uci -q set zerotier.global.enabled='0'
fi

uci commit luci
uci commit system
uci commit firewall
[ -x /etc/init.d/miniupnpd ] && uci commit upnpd
uci commit network
uci commit dropbear
uci commit dhcp
[ -x /etc/init.d/zerotier ] && uci commit zerotier

/etc/init.d/firewall restart || true
[ -x /etc/init.d/miniupnpd ] && /etc/init.d/miniupnpd disable 2>/dev/null || true
[ -x /etc/init.d/miniupnpd ] && /etc/init.d/miniupnpd stop 2>/dev/null || true
[ -x /etc/init.d/zerotier ] && /etc/init.d/zerotier disable 2>/dev/null || true
[ -x /etc/init.d/zerotier ] && /etc/init.d/zerotier stop 2>/dev/null || true
[ -x /etc/init.d/led ] && /etc/init.d/led restart 2>/dev/null || true

exit 0
