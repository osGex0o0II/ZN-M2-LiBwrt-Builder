#!/usr/bin/env bash
set -euo pipefail

# USB 仅用于供电，不保留数据功能，两个变体均禁用。
# 禁用节点（target/linux/qualcommax/dts/ipq6000-m2.dts）：
#   &usb2 / &usb3 — USB 2.0/3.0 控制器
#   &qusb_phy_0 / &qusb_phy_1 / &ssphy_0 — 配套 PHY
# 幂等性：已有 status="disabled" 标记时跳过，不重复追加
echo "========== Disable ZN-M2 USB controllers =========="
if ! grep -qE '&usb2\s*\{[^}]*status\s*=\s*"disabled"' target/linux/qualcommax/dts/ipq6000-m2.dts; then
	cat >> target/linux/qualcommax/dts/ipq6000-m2.dts << 'DTSEND'

&usb2 { status = "disabled"; };
&usb3 { status = "disabled"; };
&qusb_phy_0 { status = "disabled"; };
&qusb_phy_1 { status = "disabled"; };
&ssphy_0 { status = "disabled"; };
DTSEND
	echo "USB nodes disabled in ZN-M2 DTS"
else
	echo "USB nodes already disabled, skip"
fi

echo "========== Inject Aurora theme =========="
rm -rf package/luci-theme-aurora
git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora package/luci-theme-aurora

# Fix: 内核 6.12.91 新增 ALLOC_SKB_PAGE_FRAG_DISABLE，上游 config-6.12 未覆盖，
#      导致 make syncconfig 在 (NEW) 符号上非交互退出，编译立即失败。
if ! grep -q '^CONFIG_ALLOC_SKB_PAGE_FRAG_DISABLE=' target/linux/qualcommax/config-6.12; then
	echo "CONFIG_ALLOC_SKB_PAGE_FRAG_DISABLE=n" >> target/linux/qualcommax/config-6.12
	echo "Added CONFIG_ALLOC_SKB_PAGE_FRAG_DISABLE=n to qualcommax/config-6.12"
fi

# Fix: sch_fq 编译为内建（=y 而非 =m），确保 sysctl 在启动早期即可设置
#       net.core.default_qdisc=fq。kmod-sched-core 默认将其设为 =m 模块，
#       sysctl init (S11) 运行时尚无模块加载，/proc/sys/net/core/default_qdisc
#       不接受 fq 值，导致 sysctl 写错误并中断整个 conf 文件的后续处理。
if ! grep -q '^CONFIG_NET_SCH_FQ=' target/linux/qualcommax/config-6.12; then
	echo "CONFIG_NET_SCH_FQ=y" >> target/linux/qualcommax/config-6.12
	echo "Set CONFIG_NET_SCH_FQ=y in qualcommax/config-6.12"
fi

if [ "${INCLUDE_HOMEPROXY:-1}" != "1" ]; then
  echo "========== Skip HomeProxy for this build variant =========="
  exit 0
fi

echo "========== Replace HomeProxy for sing-box 1.12 =========="
rm -rf \
  feeds/luci/applications/luci-app-homeproxy \
  package/feeds/luci/luci-app-homeproxy \
  package/luci-app-homeproxy

# Pin to a known-good commit for reproducible builds.
# Update this periodically after verifying the new revision works.
HOMEPROXY_COMMIT="29f61caf303cd3a7051e26055dc97fdf4890e2b0"
git clone --depth=1 https://github.com/immortalwrt/homeproxy package/luci-app-homeproxy
cd package/luci-app-homeproxy
git -c advice.detachedHead=false checkout "$HOMEPROXY_COMMIT"
cd "$OLDPWD"

if [ ! -f package/luci-app-homeproxy/Makefile ]; then
  echo "ERROR: HomeProxy Makefile not found after clone" >&2
  exit 1
fi

echo "========== Custom package sources ready =========="
