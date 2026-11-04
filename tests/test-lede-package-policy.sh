#!/bin/sh
# LEDE ships a desktop/ISP package default. The router image must not inherit
# it, so keep an explicit deny list and a small allow list under test.
set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
config="$repo_root/configs/zn-m2-lede-master-nss.config"

[ -f "$config" ] || { echo "missing $config" >&2; exit 1; }

fail=0

for pkg in \
	vsftpd luci-app-vsftpd \
	vlmcsd luci-app-vlmcsd \
	luci-app-ssr-plus \
	3proxy dns2tcp ipt2socks microsocks \
	luci-app-filetransfer luci-app-rclone \
	luci-app-arpbind \
	luci-app-nlbwmon nlbwmon; do
	if ! grep -qx "CONFIG_PACKAGE_${pkg}=n" "$config"; then
		echo "FAIL: ${pkg} must be disabled" >&2
		fail=1
	fi
done

# ssr-plus helper options select 3proxy even when the parent package is off.
for opt in \
	luci-app-ssr-plus_INCLUDE_Http_Proxy \
	luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Client \
	luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Server \
	luci-app-ssr-plus_INCLUDE_NONE_V2RAY \
	luci-app-ssr-plus_Nftables_Transparent_Proxy; do
	if ! grep -qx "CONFIG_PACKAGE_${opt}=n" "$config"; then
		echo "FAIL: ${opt} must be disabled or it re-selects 3proxy" >&2
		fail=1
	fi
done

# The curated feature set must stay enabled.
for pkg in \
	luci-app-homeproxy sing-box \
	luci-theme-aurora \
	kmod-qca-nss-ecm kmod-qca-nss-drv nss-firmware-ipq6018; do
	if ! grep -qx "CONFIG_PACKAGE_${pkg}=y" "$config"; then
		echo "FAIL: ${pkg} must stay enabled" >&2
		fail=1
	fi
done

[ "$fail" -eq 0 ]
echo "lede package policy test passed"
