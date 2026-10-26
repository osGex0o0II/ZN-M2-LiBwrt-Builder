#!/usr/bin/env bash
set -euo pipefail

# Customisation script for the ZN-M2 256M / ImmortalWrt 6.18 (no NSS) profile.
# Keep this separate from libwrt-6.12.sh: the 6.12 tree is LiBwrt (NSS feed, dts/ under
# files/, 991 network guard), while this tree has no NSS and stores board DTS
# files in target/linux/qualcommax/dts/.

KERNEL_VER="$(grep -E '^KERNEL_PATCHVER:=' target/linux/qualcommax/Makefile 2>/dev/null | sed 's/.*:=//;s/^[[:space:]]*//')"
if [ "${KERNEL_VER}" != "6.18" ]; then
	echo "ERROR: expected the 6.18 tree, found KERNEL_PATCHVER='${KERNEL_VER:-missing}'" >&2
	exit 1
fi
KERNEL_CFG="target/linux/qualcommax/config-${KERNEL_VER}"
DTS_FILE="target/linux/qualcommax/dts/ipq6000-m2.dts"
IMAGE_MK="target/linux/qualcommax/image/ipq60xx.mk"
TARGET_MK="target/linux/qualcommax/ipq60xx/target.mk"

require_file() {
	if [ ! -f "$1" ]; then
		echo "ERROR: required file is missing: $1" >&2
		exit 1
	fi
}

require_file "$DTS_FILE"
require_file "$IMAGE_MK"
require_file "$TARGET_MK"

QUALCOMMAX_MAKEFILE="target/linux/qualcommax/Makefile"
require_file "$QUALCOMMAX_MAKEFILE"

# The qualcommax target force-adds WiFi, USB, storage, and PHY packages through
# DEFAULT_PACKAGES. Those are outside the .config selection, so filter them out
# before the target is evaluated.
if ! grep -q 'ZN_M2_6_18_DEFAULT_PACKAGE_FILTER' "$QUALCOMMAX_MAKEFILE"; then
	cp "$QUALCOMMAX_MAKEFILE" "${QUALCOMMAX_MAKEFILE}.builder.bak"
	excludes="wpad-openssl
kmod-ath11k
kmod-ath11k-ahb
kmod-ath11k-pci
kmod-usb3
kmod-usb-dwc3
kmod-usb-dwc3-qcom
kmod-usb-serial-qualcomm
kmod-phy-aquantia
kmod-leds-pwm
e2fsprogs
f2fs-tools
losetup
kmod-fs-ext4
kmod-fs-f2fs
automount"
	filter_args=""
	for pkg in $excludes; do
		filter_args="${filter_args} ${pkg}"
	done
	awk -v filter_args="$filter_args" '
		$0 == "$(eval $(call BuildTarget))" && !inserted {
			print ""
			print "# ZN_M2_6_18_DEFAULT_PACKAGE_FILTER"
			print "DEFAULT_PACKAGES := $(filter-out" filter_args ",$(DEFAULT_PACKAGES))"
			inserted = 1
		}
		{ print }
	' "$QUALCOMMAX_MAKEFILE" > "${QUALCOMMAX_MAKEFILE}.tmp"
	mv "${QUALCOMMAX_MAKEFILE}.tmp" "$QUALCOMMAX_MAKEFILE"
	if ! grep -q 'ZN_M2_6_18_DEFAULT_PACKAGE_FILTER' "$QUALCOMMAX_MAKEFILE"; then
		echo "ERROR: qualcommax Makefile changed; the 6.18 default package filter was not inserted" >&2
		exit 1
	fi
	echo "Filtered 6.18 qualcommax default packages:${filter_args}"
else
	echo "6.18 qualcommax default package filter already present, skip"
fi

echo "========== ZN-M2 6.18 wired-only hardware =========="
# Disable WiFi and USB3, and apply the hardware-verified 16 MiB Q6 carveout.
# The NSS reserved-memory node (16 MiB at 0x40000000) is intentionally left in
# place: the 6.18 tree has no NSS driver, but the reservation is part of the
# board memory map and costs no extra work to keep.
if ! grep -q '6.18_WIRED_ONLY_16M' "$DTS_FILE"; then
	cp "$DTS_FILE" "${DTS_FILE}.bak"
	cat >> "$DTS_FILE" << 'DTSEND'

/* 6.18_WIRED_ONLY_16M */
&wifi { status = "disabled"; };
&usb3 { status = "disabled"; };
&qusb_phy_0 { status = "disabled"; };
&ssphy_0 { status = "disabled"; };
&q6_region { reg = <0x0 0x4ab00000 0x0 0x1000000>; };
&q6_etr_region { reg = <0x0 0x4bb00000 0x0 0x100000>; };
&m3_dump_region { reg = <0x0 0x4bc00000 0x0 0x100000>; };
&ramoops_region { reg = <0x0 0x4bd00000 0x0 0x100000>; };
DTSEND
	echo "WiFi/USB disabled and Q6 shrunk to 16 MiB in the board DTS"
else
	echo "6.18 wired-only DTS overrides already present, skip"
fi

# Drop the board WiFi calibration package and the subtarget's ath11k firmware
# default. The config also sets the packages to =n, but DEVICE_PACKAGES and
# DEFAULT_PACKAGES are appended outside the .config selection and must be
# removed from the image/target metadata directly.
if grep -q '^DEFAULT_PACKAGES += ath11k-firmware-ipq6018-ddwrt$' "$TARGET_MK"; then
	sed -i '/^DEFAULT_PACKAGES += ath11k-firmware-ipq6018-ddwrt$/d' "$TARGET_MK"
	echo "Removed the ath11k firmware default from ${TARGET_MK}"
fi
if awk '/^define Device\/zn_m2$/{f=1} f&&/^endef$/{print;exit} f' "$IMAGE_MK" |
	grep -q 'DEVICE_PACKAGES := ipq-wifi-zn_m2'; then
	awk '
		/^define Device\/zn_m2$/ { in_zn = 1; print; next }
		in_zn && /^endef$/ { in_zn = 0; print; next }
		in_zn && /DEVICE_PACKAGES := ipq-wifi-zn_m2/ {
			sub(/DEVICE_PACKAGES := ipq-wifi-zn_m2/, "DEVICE_PACKAGES :=")
			print
			next
		}
		{ print }
	' "$IMAGE_MK" > "${IMAGE_MK}.tmp"
	mv "${IMAGE_MK}.tmp" "$IMAGE_MK"
	echo "Removed ipq-wifi-zn_m2 from the zn_m2 device packages"
fi
if awk '/^define Device\/zn_m2$/{f=1} f&&/^endef$/{print;exit} f' "$IMAGE_MK" |
	grep -q 'ipq-wifi-zn_m2'; then
	echo "ERROR: zn_m2 device packages still reference ipq-wifi-zn_m2" >&2
	exit 1
fi

# fq must be built in so the sysctl setting is available before modules load.
if ! grep -q '^CONFIG_NET_SCH_FQ=' "${KERNEL_CFG}" 2>/dev/null; then
	echo "CONFIG_NET_SCH_FQ=y" >> "${KERNEL_CFG}"
	echo "Set CONFIG_NET_SCH_FQ=y in ${KERNEL_CFG}"
fi
for symbol in CONFIG_IKCONFIG CONFIG_IKCONFIG_PROC; do
	if ! grep -q "^${symbol}=" "${KERNEL_CFG}" 2>/dev/null; then
		echo "${symbol}=y" >> "${KERNEL_CFG}"
		echo "Set ${symbol}=y in ${KERNEL_CFG}"
	fi
done

# 256KB kernel log buffer (the target default is 128KB) so a panic/OOM leaves
# enough dmesg context for post-mortem analysis.
if grep -q '^CONFIG_LOG_BUF_SHIFT=' "${KERNEL_CFG}" 2>/dev/null; then
	if ! grep -qx 'CONFIG_LOG_BUF_SHIFT=18' "${KERNEL_CFG}"; then
		sed -i 's/^CONFIG_LOG_BUF_SHIFT=.*/CONFIG_LOG_BUF_SHIFT=18/' "${KERNEL_CFG}"
		echo "Set CONFIG_LOG_BUF_SHIFT=18 in ${KERNEL_CFG}"
	fi
else
	echo "CONFIG_LOG_BUF_SHIFT=18" >> "${KERNEL_CFG}"
	echo "Set CONFIG_LOG_BUF_SHIFT=18 in ${KERNEL_CFG}"
fi

echo "========== Inject Aurora theme =========="
rm -rf package/luci-theme-aurora
AURORA_COMMIT="${AURORA_COMMIT:-}"
if ! printf '%s\n' "$AURORA_COMMIT" | grep -Eq '^[0-9a-f]{40}$'; then
	echo "ERROR: Missing or invalid AURORA_COMMIT pin; load deps/immortalwrt-6.18.env" >&2
	exit 1
fi
if [ -n "${GITHUB_ENV:-}" ]; then
	echo "AURORA_COMMIT=${AURORA_COMMIT}" >> "$GITHUB_ENV"
fi
if ! git clone https://github.com/eamonxg/luci-theme-aurora package/luci-theme-aurora; then
	rm -rf package/luci-theme-aurora
	echo "ERROR: Failed to clone luci-theme-aurora" >&2
	exit 1
fi
cd package/luci-theme-aurora
git -c advice.detachedHead=false checkout "$AURORA_COMMIT"
cd "$OLDPWD" || exit 1

if [ "${INCLUDE_HOMEPROXY:-1}" != "1" ]; then
	echo "========== Skip HomeProxy and sing-box for this build =========="
	exit 0
fi

echo "========== Use pinned VIKINGYFY HomeProxy and sing-box =========="
rm -rf \
	package/luci-app-homeproxy \
	package/network/services/sing-box \
	package/feeds/luci/luci-app-homeproxy \
	package/feeds/packages/sing-box \
	package/feeds/packages/sing-box-tiny

HOMEPROXY_FEED_DIR="feeds/vikingfy/luci-app-homeproxy"
HOMEPROXY_PACKAGE_LINK="package/feeds/vikingfy/luci-app-homeproxy"
SING_BOX_FEED_DIR="feeds/vikingfy/sing-box"
SING_BOX_PACKAGE_LINK="package/feeds/vikingfy/sing-box"

[ -e "$HOMEPROXY_PACKAGE_LINK" ] || \
	ln -sfn "$(pwd)/$HOMEPROXY_FEED_DIR" "$HOMEPROXY_PACKAGE_LINK"
[ -e "$SING_BOX_PACKAGE_LINK" ] || \
	ln -sfn "$(pwd)/$SING_BOX_FEED_DIR" "$SING_BOX_PACKAGE_LINK"

for required_path in \
	"$HOMEPROXY_FEED_DIR/Makefile" \
	"$SING_BOX_FEED_DIR/Makefile" \
	"$HOMEPROXY_PACKAGE_LINK" \
	"$SING_BOX_PACKAGE_LINK"; do
	if [ ! -e "$required_path" ]; then
		echo "ERROR: Required pinned VIKINGYFY path is missing: ${required_path}" >&2
		exit 1
	fi
done

if [ "$(readlink -f "$HOMEPROXY_PACKAGE_LINK")" != "$(readlink -f "$HOMEPROXY_FEED_DIR")" ]; then
	echo "ERROR: Installed HomeProxy package does not resolve to the pinned VIKINGYFY feed" >&2
	exit 1
fi
if [ "$(readlink -f "$SING_BOX_PACKAGE_LINK")" != "$(readlink -f "$SING_BOX_FEED_DIR")" ]; then
	echo "ERROR: Installed sing-box package does not resolve to the pinned VIKINGYFY feed" >&2
	exit 1
fi

if ! grep -Eq '^LUCI_EXTRA_DEPENDS:=sing-box \(>=' "$HOMEPROXY_FEED_DIR/Makefile"; then
	echo "ERROR: Pinned VIKINGYFY HomeProxy does not declare its sing-box version floor" >&2
	exit 1
fi
if ! grep -Fq 'PKG_UPSTREAM_VERSION:=' "$SING_BOX_FEED_DIR/Makefile"; then
	echo "ERROR: Pinned VIKINGYFY sing-box package metadata is missing" >&2
	exit 1
fi

echo "Pinned VIKINGYFY HomeProxy and sing-box selected"
echo "========== Custom package sources ready =========="
