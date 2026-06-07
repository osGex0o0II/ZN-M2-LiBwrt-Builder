#!/usr/bin/env bash
set -euo pipefail

# USB 仅用于供电，不保留数据功能，两个变体均禁用。
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

if [ "${INCLUDE_HOMEPROXY:-1}" != "1" ]; then
  echo "========== Skip HomeProxy for this build variant =========="
  exit 0
fi

echo "========== Replace HomeProxy for sing-box 1.12 =========="
rm -rf \
  feeds/luci/applications/luci-app-homeproxy \
  package/feeds/luci/luci-app-homeproxy \
  package/luci-app-homeproxy

git clone --depth=1 https://github.com/immortalwrt/homeproxy package/luci-app-homeproxy

if [ ! -f package/luci-app-homeproxy/Makefile ]; then
  echo "ERROR: HomeProxy Makefile not found after clone" >&2
  exit 1
fi

echo "========== Custom package sources ready =========="
