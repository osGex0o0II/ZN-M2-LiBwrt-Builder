#!/usr/bin/env bash
set -euo pipefail

# 动态检测内核主版本（6.12、6.18 等），避免硬编码路径
# 权威来源：target/linux/qualcommax/Makefile 中的 KERNEL_PATCHVER
# 优先从 qualcommax 目标 Makefile 中获取 KERNEL_PATCHVER。
# 兜底：使用 git show 从源码目录推断（通过 KERNEL_VER_VAR 传入），
# 或硬编码为主流内核版本。
KERNEL_VER="$(grep -E '^KERNEL_PATCHVER:=' target/linux/qualcommax/Makefile 2>/dev/null | sed 's/.*:=//;s/^[[:space:]]*//')"
if [ -z "$KERNEL_VER" ]; then
  # 兜底从 generic 目录的 kernel-* 文件名推断（OpenWrt 中是文件，非目录）
  KERNEL_VER="$(find target/linux/generic/ -maxdepth 1 -name 'kernel-*' 2>/dev/null | head -1 | sed 's/.*kernel-//')"
fi
if [ -z "$KERNEL_VER" ]; then
  echo "WARNING: Could not detect kernel version, falling back to 6.12" >&2
  KERNEL_VER="6.12"
fi
KERNEL_CFG="target/linux/qualcommax/config-${KERNEL_VER}"
echo "========== Detected kernel ${KERNEL_VER} (config: ${KERNEL_CFG}) =========="

DTS_FILE="target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6000-m2.dts"
LEDS_FILE="target/linux/qualcommax/ipq60xx/base-files/etc/board.d/01_leds"
QUALCOMMAX_MAKEFILE="target/linux/qualcommax/Makefile"
IPQ60XX_TARGET_MAKEFILE="target/linux/qualcommax/ipq60xx/target.mk"
DROPBEAR_BLANK_ROOT_PATCH="package/network/services/dropbear/patches/600-allow-blank-root-password.patch"
DROPBEAR_BLANK_ROOT_PATCH_SHA256="309ab82c4656d9f8b9519cd0e59a9a82e1d9ae4838daef2a9b10fe55ed213ac4"
QUALCOMMAX_NETWORK_DEFAULT="target/linux/qualcommax/base-files/etc/uci-defaults/991_set-network.sh"
QUALCOMMAX_NETWORK_DEFAULT_SHA256="da8f39e259d537f2feb2522503fa2b408824f335f84bdf619d8ea11eed33eec0"

ZN_M2_COMMON_DEFAULT_PACKAGE_EXCLUDES="
wpad-openssl
kmod-ath11k
kmod-ath11k-ahb
kmod-ath11k-pci
ath11k-firmware-ipq6018
kmod-usb3
kmod-usb-dwc3
kmod-usb-dwc3-qcom
kmod-qca-nss-drv-eogremgr
kmod-qca-nss-drv-gre
kmod-qca-nss-drv-l2tpv2
kmod-qca-nss-drv-map-t
kmod-qca-nss-drv-match
kmod-qca-nss-drv-mirror
kmod-qca-nss-drv-netlink
kmod-qca-nss-drv-pptp
kmod-qca-nss-drv-tun6rd
kmod-qca-nss-drv-tunipip6
kmod-qca-nss-drv-vxlanmgr
kmod-qca-nss-drv-wifi-meshmgr
"

ZN_M2_256M_DEFAULT_PACKAGE_EXCLUDES="
automount
e2fsprogs
f2fs-tools
shellsync
losetup
kmod-fs-ext4
kmod-fs-f2fs
kmod-leds-pwm
kmod-macvlan
kmod-mppe
kmod-phy-aquantia
kmod-qca-nss-crypto
nss-eip-firmware
"

load_pinned_deps() {
	for candidate in \
		"${PINNED_DEPS_FILE:-}" \
		"${GITHUB_WORKSPACE:-}/deps/pinned-deps.env" \
		"../deps/pinned-deps.env" \
		"deps/pinned-deps.env"; do
		[ -n "$candidate" ] || continue
		[ -f "$candidate" ] || continue
		# shellcheck disable=SC1090
		. "$candidate"
		echo "Loaded pinned dependencies from ${candidate}"
		return 0
	done
}

load_pinned_deps

remove_blank_root_ssh_patch() {
	echo "========== Disable blank-password root SSH authentication =========="
	if [ ! -f "$DROPBEAR_BLANK_ROOT_PATCH" ]; then
		echo "ERROR: Expected LiBwrt blank-root Dropbear patch is missing; review upstream authentication behavior" >&2
		exit 1
	fi

	local actual_sha256
	actual_sha256="$(sha256sum "$DROPBEAR_BLANK_ROOT_PATCH" | awk '{print $1}')"
	if [ "$actual_sha256" != "$DROPBEAR_BLANK_ROOT_PATCH_SHA256" ]; then
		echo "ERROR: LiBwrt blank-root Dropbear patch changed; refusing an unaudited authentication bypass" >&2
		echo "  Expected: ${DROPBEAR_BLANK_ROOT_PATCH_SHA256}" >&2
		echo "  Got:      ${actual_sha256}" >&2
		exit 1
	fi

	rm -f "$DROPBEAR_BLANK_ROOT_PATCH"
	echo "Removed LiBwrt blank-password root SSH exception"
}

guard_qualcommax_network_defaults() {
	echo "========== Preserve administrator network settings across sysupgrade =========="
	local builder_root
	local patch_file
	local actual_sha256
	builder_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	patch_file="$builder_root/patches/qualcommax/preserve-network-settings.patch"

	if [ ! -f "$QUALCOMMAX_NETWORK_DEFAULT" ]; then
		echo "ERROR: Missing LiBwrt qualcommax network defaults: ${QUALCOMMAX_NETWORK_DEFAULT}" >&2
		exit 1
	fi
	if [ ! -f "$patch_file" ]; then
		echo "ERROR: Missing preserved-network guard patch: ${patch_file}" >&2
		exit 1
	fi

	if git apply --check "$patch_file" 2>/dev/null; then
		actual_sha256="$(sha256sum "$QUALCOMMAX_NETWORK_DEFAULT" | awk '{print $1}')"
		if [ "$actual_sha256" != "$QUALCOMMAX_NETWORK_DEFAULT_SHA256" ]; then
			echo "ERROR: LiBwrt qualcommax network defaults changed; review before patching" >&2
			exit 1
		fi
		git apply "$patch_file"
		echo "Guarded LiBwrt qualcommax factory network defaults"
	elif git apply --reverse --check "$patch_file" 2>/dev/null; then
		echo "LiBwrt qualcommax network defaults already guarded, skip"
	else
		echo "ERROR: Preserved-network guard no longer applies cleanly" >&2
		exit 1
	fi

	if ! grep -Fq 'ZN_M2_PRESERVE_CONFIG_GUARD' "$QUALCOMMAX_NETWORK_DEFAULT"; then
		echo "ERROR: Preserved-network guard is missing after patch" >&2
		exit 1
	fi
}

require_zn_m2_dts_file() {
	if [ ! -f "$DTS_FILE" ]; then
		echo "ERROR: Missing ZN-M2 DTS file: ${DTS_FILE}" >&2
		exit 1
	fi

	if ! grep -q 'ipq6000-cmiot.dtsi' "$DTS_FILE"; then
		echo "WARNING: ${DTS_FILE} no longer includes ipq6000-cmiot.dtsi; USB label references will be validated by dtc during build." >&2
	fi
}

patch_zn_m2_wired_only_hardware() {
	echo "========== Disable ZN-M2 Wi-Fi hardware and LED bindings =========="
	require_zn_m2_dts_file

	if ! grep -q 'WIFI_DISABLED_BY_BUILDER' "$DTS_FILE" 2>/dev/null; then
		cp "$DTS_FILE" "${DTS_FILE}.wifi.bak"
		cat >> "$DTS_FILE" << 'DTSEND'

/* WIFI_DISABLED_BY_BUILDER */
&wifi { status = "disabled"; };
DTSEND
		echo "Wi-Fi node disabled in ZN-M2 DTS"
	else
		echo "Wi-Fi node already disabled, skip"
	fi

	# The 256M profile is permanently wired-only. Disabling the Wi-Fi node alone
	# still boots the WCSS Q6 remoteproc and reserves its firmware carveout.
	# The carveout must stay reserved: the platform requires its memory to remain
	# reserved even while the subsystem is unused (the same reason qualcommax
	# reserves the NSS region). Deleting the reservation lets the kernel allocate
	# that memory and the board then boot-loops with silent watchdog resets.
	# Instead, shrink the carveout to the size used by the upstream 256M memory
	# profile (40 MiB) so the remaining 15 MiB is released to the kernel. Keep
	# this 256M-only to avoid changing the memory map of the 1G variant.
	if [ "${VARIANT_FILES:-}" = "files-256m" ]; then
		if ! grep -q 'WCSS_DISABLED_BY_BUILDER' "$DTS_FILE" 2>/dev/null; then
			cat >> "$DTS_FILE" << 'DTSEND'

/* WCSS_DISABLED_BY_BUILDER */
&q6v5_wcss {
	status = "disabled";
	/delete-property/ memory-region;
};

/* Keep 40 MiB of the Q6 firmware carveout reserved for platform stability
 * (matches the upstream 256M memory profile) and release the rest. */
&q6_region {
	reg = <0x0 0x4ab00000 0x0 0x2800000>;
};
DTSEND
			echo "WCSS Q6 disabled and its carveout shrunk to 40 MiB for the 256M profile"
		else
			echo "WCSS Q6 carveout already shrunk, skip"
		fi
	fi

	if [ ! -f "$LEDS_FILE" ]; then
		echo "ERROR: Missing ZN-M2 LED board file: ${LEDS_FILE}" >&2
		exit 1
	fi
	# board_detect sources every file under /etc/board.d/*. A backup left next
	# to 01_leds would be executed on-device and can restore stale LED entries.
	rm -f "${LEDS_FILE}".*.bak "${LEDS_FILE}.wifi.bak" 2>/dev/null || true

	if sed -n '/zn,m2)/,/;;/p' "$LEDS_FILE" | grep -q 'phy[01]-ap0'; then
		awk '
			$0 == "cmiot,ax18|\\" {
				print "cmiot,ax18)"
				in_zn_m2_shared_block = 1
				next
			}
			in_zn_m2_shared_block && $0 == "zn,m2)" {
				next
			}
			in_zn_m2_shared_block && /ucidef_set_led_netdev "lan"/ {
				print
				print "\t;;"
				print "zn,m2)"
				print "\tucidef_set_led_netdev \"wan\" \"WAN\" \"blue:wan\" \"wan\""
				print "\tucidef_set_led_netdev \"lan\" \"LAN\" \"blue:lan\" \"br-lan\""
				in_zn_m2_shared_block = 2
				next
			}
			in_zn_m2_shared_block == 2 && $0 == "\t;;" {
				print "\t;;"
				in_zn_m2_shared_block = 0
				next
			}
			{ print }
		' "$LEDS_FILE" > "${LEDS_FILE}.tmp"
		mv "${LEDS_FILE}.tmp" "$LEDS_FILE"
		if sed -n '/zn,m2)/,/;;/p' "$LEDS_FILE" | grep -q 'phy[01]-ap0'; then
			echo "ERROR: ZN-M2 wireless LED bindings still reference phy0-ap0/phy1-ap0" >&2
			exit 1
		fi
		echo "Wireless LED netdev bindings removed for ZN-M2"
	else
		echo "Wireless LED netdev bindings already absent, skip"
	fi
	if find "$(dirname "$LEDS_FILE")" -maxdepth 1 -type f -name '01_leds*.bak' | grep -q .; then
		echo "ERROR: Backup files under board.d would be executed by board_detect" >&2
		find "$(dirname "$LEDS_FILE")" -maxdepth 1 -type f -name '01_leds*.bak' >&2
		exit 1
	fi
}

patch_qualcommax_default_packages() {
	echo "========== Slim qualcommax default packages for wired ZN-M2 =========="
	if [ ! -f "$QUALCOMMAX_MAKEFILE" ]; then
		echo "ERROR: Missing qualcommax Makefile: ${QUALCOMMAX_MAKEFILE}" >&2
		exit 1
	fi

	local excludes="$ZN_M2_COMMON_DEFAULT_PACKAGE_EXCLUDES"
	if [ "${VARIANT_FILES:-}" = "files-256m" ]; then
		excludes="${excludes}
${ZN_M2_256M_DEFAULT_PACKAGE_EXCLUDES}"
	fi

	local filter_args=""
	local pkg
	for pkg in $excludes; do
		filter_args="${filter_args} ${pkg}"
	done

	if ! grep -q 'ZN_M2_DEFAULT_PACKAGE_FILTER' "$QUALCOMMAX_MAKEFILE"; then
		cp "$QUALCOMMAX_MAKEFILE" "${QUALCOMMAX_MAKEFILE}.builder.bak"
		awk -v filter_args="$filter_args" '
			$0 == "$(eval $(call BuildTarget))" && !inserted {
				print ""
				print "# ZN_M2_DEFAULT_PACKAGE_FILTER"
				print "DEFAULT_PACKAGES := $(filter-out" filter_args ",$(DEFAULT_PACKAGES))"
				inserted = 1
			}
			{ print }
		' "$QUALCOMMAX_MAKEFILE" > "${QUALCOMMAX_MAKEFILE}.tmp"
		mv "${QUALCOMMAX_MAKEFILE}.tmp" "$QUALCOMMAX_MAKEFILE"
		if ! grep -q 'ZN_M2_DEFAULT_PACKAGE_FILTER' "$QUALCOMMAX_MAKEFILE"; then
			echo "ERROR: qualcommax Makefile changed; default package filter was not inserted" >&2
			exit 1
		fi
		echo "Filtered qualcommax default packages:${filter_args}"
	else
		echo "qualcommax default package filter already present, skip"
	fi

	if [ -f "$IPQ60XX_TARGET_MAKEFILE" ] && ! grep -q 'ZN_M2_IPQ60XX_DEFAULT_PACKAGE_FILTER' "$IPQ60XX_TARGET_MAKEFILE"; then
		cp "$IPQ60XX_TARGET_MAKEFILE" "${IPQ60XX_TARGET_MAKEFILE}.builder.bak"
		awk -v filter_args="$filter_args" '
			/^define Target\/Description/ && !inserted {
				print ""
				print "# ZN_M2_IPQ60XX_DEFAULT_PACKAGE_FILTER"
				print "DEFAULT_PACKAGES := $(filter-out" filter_args ",$(DEFAULT_PACKAGES))"
				inserted = 1
			}
			{ print }
		' "$IPQ60XX_TARGET_MAKEFILE" > "${IPQ60XX_TARGET_MAKEFILE}.tmp"
		mv "${IPQ60XX_TARGET_MAKEFILE}.tmp" "$IPQ60XX_TARGET_MAKEFILE"
		if ! grep -q 'ZN_M2_IPQ60XX_DEFAULT_PACKAGE_FILTER' "$IPQ60XX_TARGET_MAKEFILE"; then
			echo "ERROR: ipq60xx target.mk changed; default package filter was not inserted" >&2
			exit 1
		fi
		echo "Filtered ipq60xx default packages:${filter_args}"
	fi
}

patch_nss_build_dependencies() {
	echo "========== Track NSS compile options in package build stamps =========="
	local nss_feed_dir="feeds/nss_packages"
	local driver_makefile="$nss_feed_dir/qca-nss-drv/Makefile"
	local ecm_makefile="$nss_feed_dir/qca-nss-ecm/Makefile"
	local builder_root
	local patch_file
	builder_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	patch_file="$builder_root/patches/qca-nss-drv/profile-config-depends.patch"

	if [ ! -f "$driver_makefile" ]; then
		echo "ERROR: Missing qca-nss-drv feed Makefile: ${driver_makefile}" >&2
		exit 1
	fi
	if [ ! -f "$patch_file" ]; then
		echo "ERROR: Missing qca-nss-drv profile dependency patch: ${patch_file}" >&2
		exit 1
	fi

	if git -C "$nss_feed_dir" apply --check "$patch_file" 2>/dev/null; then
		git -C "$nss_feed_dir" apply "$patch_file"
		echo "Applied qca-nss-drv profile dependency patch"
	elif git -C "$nss_feed_dir" apply --reverse --check "$patch_file" 2>/dev/null; then
		echo "qca-nss-drv profile dependency patch already applied, skip"
	else
		echo "ERROR: qca-nss-drv feed changed; profile dependency patch no longer applies cleanly" >&2
		exit 1
	fi

	local config_deps
	local profile
	config_deps="$(sed -n '/^PKG_CONFIG_DEPENDS:=/,/^$/p' "$driver_makefile")"
	for profile in HIGH MEDIUM LOW; do
		if ! printf '%s\n' "$config_deps" | grep -Fq "CONFIG_NSS_MEM_PROFILE_${profile}"; then
			echo "ERROR: NSS ${profile} profile is missing from qca-nss-drv PKG_CONFIG_DEPENDS" >&2
			exit 1
		fi
	done
	if ! printf '%s\n' "$config_deps" | grep -Fq 'CONFIG_NSS_FIRMWARE_VERSION_12_5'; then
		echo "ERROR: NSS 12.5 firmware version is missing from qca-nss-drv PKG_CONFIG_DEPENDS" >&2
		exit 1
	fi

	patch_file="$builder_root/patches/qca-nss-ecm/firmware-config-depends.patch"
	if [ ! -f "$ecm_makefile" ]; then
		echo "ERROR: Missing qca-nss-ecm feed Makefile: ${ecm_makefile}" >&2
		exit 1
	fi
	if [ ! -f "$patch_file" ]; then
		echo "ERROR: Missing qca-nss-ecm firmware dependency patch: ${patch_file}" >&2
		exit 1
	fi
	if git -C "$nss_feed_dir" apply --check "$patch_file" 2>/dev/null; then
		git -C "$nss_feed_dir" apply "$patch_file"
		echo "Applied qca-nss-ecm firmware dependency patch"
	elif git -C "$nss_feed_dir" apply --reverse --check "$patch_file" 2>/dev/null; then
		echo "qca-nss-ecm firmware dependency patch already applied, skip"
	else
		echo "ERROR: qca-nss-ecm feed changed; firmware dependency patch no longer applies cleanly" >&2
		exit 1
	fi
	config_deps="$(sed -n '/^PKG_CONFIG_DEPENDS:=/,/^$/p' "$ecm_makefile")"
	if ! printf '%s\n' "$config_deps" | grep -Fq 'CONFIG_NSS_FIRMWARE_VERSION_12_5'; then
		echo "ERROR: NSS 12.5 firmware version is missing from qca-nss-ecm PKG_CONFIG_DEPENDS" >&2
		exit 1
	fi
}

patch_packages_feed_dependencies() {
	echo "========== Repair pinned packages feed recursive dependencies =========="
	local packages_feed_dir="feeds/packages"
	local builder_root
	local compatibility_lib
	builder_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	compatibility_lib="$builder_root/scripts/packages-feed-compat.sh"

	if [ ! -f "$compatibility_lib" ]; then
		echo "ERROR: Missing shared packages feed compatibility library: ${compatibility_lib}" >&2
		exit 1
	fi
	# shellcheck disable=SC1090
	. "$compatibility_lib"
	packages_feed_repair "$packages_feed_dir" "$builder_root/patches/packages"
}

patch_256m_ecm_tunnel_support() {
	if [ "${VARIANT_FILES:-}" != "files-256m" ]; then
		return 0
	fi

	echo "========== Disable unused ECM PPTP/L2TP/GRE support for 256M =========="
	local nss_feed_dir="feeds/nss_packages"
	local ecm_makefile="$nss_feed_dir/qca-nss-ecm/Makefile"
	local ecm_init="$nss_feed_dir/qca-nss-ecm/files/qca-nss-ecm.init"
	local builder_root
	local patch_file
	builder_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

	if [ ! -f "$ecm_makefile" ]; then
		echo "ERROR: Missing qca-nss-ecm feed Makefile: ${ecm_makefile}" >&2
		exit 1
	fi
	if [ ! -f "$ecm_init" ]; then
		echo "ERROR: Missing qca-nss-ecm init script: ${ecm_init}" >&2
		exit 1
	fi

	for patch_file in \
		"$builder_root/patches/qca-nss-ecm/256m-disable-pptp-l2tp.patch" \
		"$builder_root/patches/qca-nss-ecm/256m-runtime-limits.patch"; do
		if [ ! -f "$patch_file" ]; then
			echo "ERROR: Missing qca-nss-ecm 256M patch: ${patch_file}" >&2
			exit 1
		fi
		if git -C "$nss_feed_dir" apply --check "$patch_file" 2>/dev/null; then
			git -C "$nss_feed_dir" apply "$patch_file"
			echo "Applied 256M qca-nss-ecm patch: $(basename "$patch_file")"
		elif git -C "$nss_feed_dir" apply --reverse --check "$patch_file" 2>/dev/null; then
			echo "256M qca-nss-ecm patch already applied, skip: $(basename "$patch_file")"
		else
			echo "ERROR: qca-nss-ecm feed changed; patch no longer applies cleanly: ${patch_file}" >&2
			exit 1
		fi
	done

	if grep -Eq 'PACKAGE_kmod-pppoe:kmod-(pptp|pppol2tp)' "$ecm_makefile"; then
		echo "ERROR: qca-nss-ecm still forces PPTP/L2TP packages through PPPoE" >&2
		exit 1
	fi
	if grep -Eq 'ECM_INTERFACE_(PPTP|L2TPV2|L2TPV2_PPTP|GRE|GRE_TAP|GRE_TUN)_ENABLE=y' "$ecm_makefile"; then
		echo "ERROR: qca-nss-ecm still enables a PPTP/L2TP/GRE tunnel path" >&2
		exit 1
	fi

	local setting
	for setting in \
		'PACKAGE_kmod-pppoe:kmod-pppoe' \
		'ECM_FRONT_END_CONN_LIMIT_ENABLE=y' \
		'ECM_INTERFACE_PPPOE_ENABLE=y' \
		'ECM_INTERFACE_PPP_ENABLE=y' \
		'ECM_INTERFACE_PPTP_ENABLE=n' \
		'ECM_INTERFACE_L2TPV2_ENABLE=n' \
		'ECM_INTERFACE_L2TPV2_PPTP_ENABLE=n' \
		'ECM_INTERFACE_GRE_ENABLE=n' \
		'ECM_INTERFACE_GRE_TAP_ENABLE=n' \
		'ECM_INTERFACE_GRE_TUN_ENABLE=n'; do
		if ! grep -qF "$setting" "$ecm_makefile"; then
			echo "ERROR: Missing expected qca-nss-ecm setting: ${setting}" >&2
			exit 1
		fi
		done

	if ! grep -Fq 'sysctl -w net.ecm.front_end_conn_limit=1' "$ecm_init"; then
		echo "ERROR: ECM connection limit is not applied after the module loads" >&2
		exit 1
	fi
}

patch_256m_pppoe_only() {
	if [ "${VARIANT_FILES:-}" != "files-256m" ]; then
		return 0
	fi

	echo "========== Trim syncdial and MPPE from 256M PPPoE =========="
	local builder_root
	local patch_file
	local ppp_makefile="package/network/services/ppp/Makefile"
	local ppp_script="package/network/services/ppp/files/ppp.sh"
	builder_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	patch_file="$builder_root/patches/ppp/256m-pppoe-only.patch"

	if [ ! -f "$ppp_makefile" ] || [ ! -f "$ppp_script" ]; then
		echo "ERROR: LiBwrt PPP package files are missing; cannot apply the 256M PPPoE patch" >&2
		exit 1
	fi
	if [ ! -f "$patch_file" ]; then
		echo "ERROR: Missing 256M PPPoE-only patch: ${patch_file}" >&2
		exit 1
	fi

	if git apply --check "$patch_file" 2>/dev/null; then
		git apply "$patch_file"
		echo "Applied 256M PPPoE-only patch"
	elif git apply --reverse --check "$patch_file" 2>/dev/null; then
		echo "256M PPPoE-only patch already applied, skip"
	else
		echo "ERROR: LiBwrt PPP package changed; 256M PPPoE-only patch no longer applies cleanly" >&2
		exit 1
	fi

	if grep -Eq '(^|[[:space:]])(shellsync|kmod-mppe)([[:space:]]|$)' "$ppp_makefile"; then
		echo "ERROR: 256M PPP package still pulls syncdial or MPPE dependencies" >&2
		exit 1
	fi
	if grep -Eq 'syncdial|syncppp|shellsync' "$ppp_script"; then
		echo "ERROR: 256M PPPoE handler still contains syncdial support" >&2
		exit 1
	fi
}

remove_blank_root_ssh_patch
guard_qualcommax_network_defaults
patch_zn_m2_wired_only_hardware
patch_qualcommax_default_packages
patch_nss_build_dependencies
patch_packages_feed_dependencies
patch_256m_ecm_tunnel_support
patch_256m_pppoe_only

# 1G 改版带板载 USB 3.0 接口，可通过 ENABLE_USB_DATA=1 保留数据功能。
# 256M 原厂无物理 USB 接口，默认仍禁用控制器和 PHY，减少无用硬件初始化。
if [ "${ENABLE_USB_DATA:-0}" = "1" ]; then
	echo "========== Keep ZN-M2 USB controllers enabled =========="
	require_zn_m2_dts_file
	if ! grep -q 'USB_ENABLED_BY_BUILDER' "$DTS_FILE" 2>/dev/null; then
		cp "$DTS_FILE" "${DTS_FILE}.bak"
		echo "Backed up DTS to $(basename "$DTS_FILE").bak"
		cat >> "$DTS_FILE" << 'DTSEND'

/* USB_ENABLED_BY_BUILDER */
&usb2 { status = "okay"; };
&usb3 { status = "okay"; };
&qusb_phy_0 { status = "okay"; };
&qusb_phy_1 { status = "okay"; };
&ssphy_0 { status = "okay"; };
DTSEND
		echo "USB nodes enabled in ZN-M2 DTS"
	else
		echo "USB nodes already enabled, skip"
	fi
else
	# 禁用节点（target/linux/qualcommax/dts/ipq6000-m2.dts）：
	#   &usb2 / &usb3 — USB 2.0/3.0 控制器
	#   &qusb_phy_0 / &qusb_phy_1 / &ssphy_0 — 配套 PHY
	# 幂等性：用注释哨兵标记，避免正则跨行匹配问题
	echo "========== Disable ZN-M2 USB controllers =========="
	require_zn_m2_dts_file
	if ! grep -q 'USB_DISABLED_BY_BUILDER' "$DTS_FILE" 2>/dev/null; then
		cp "$DTS_FILE" "${DTS_FILE}.bak"
		echo "Backed up DTS to $(basename "$DTS_FILE").bak"
		cat >> "$DTS_FILE" << 'DTSEND'

/* USB_DISABLED_BY_BUILDER */
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
fi

echo "========== Inject Aurora theme =========="
rm -rf package/luci-theme-aurora
# The pin lives in deps/pinned-deps.env; a hardcoded fallback would silently
# drift from it, so require the pin instead.
AURORA_COMMIT="${AURORA_COMMIT:-}"
if ! printf '%s\n' "$AURORA_COMMIT" | grep -Eq '^[0-9a-f]{40}$'; then
  echo "ERROR: Missing or invalid AURORA_COMMIT pin; load deps/pinned-deps.env" >&2
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

# Fix: 内核新增 ALLOC_SKB_PAGE_FRAG_DISABLE，上游 config 未覆盖，
#      导致 make syncconfig 在 (NEW) 符号上非交互退出，编译立即失败。
if ! grep -q "^CONFIG_ALLOC_SKB_PAGE_FRAG_DISABLE=" "${KERNEL_CFG}" 2>/dev/null; then
	echo "CONFIG_ALLOC_SKB_PAGE_FRAG_DISABLE=n" >> "${KERNEL_CFG}"
	echo "Added CONFIG_ALLOC_SKB_PAGE_FRAG_DISABLE=n to ${KERNEL_CFG}"
fi

# Fix: sch_fq 编译为内建（=y 而非 =m），确保 sysctl 在启动早期即可设置
#       net.core.default_qdisc=fq。kmod-sched-core 默认将其设为 =m 模块，
#       sysctl init (S11) 运行时尚无模块加载，/proc/sys/net/core/default_qdisc
#       不接受 fq 值，导致 sysctl 写错误并中断整个 conf 文件的后续处理。
if ! grep -q '^CONFIG_NET_SCH_FQ=' "${KERNEL_CFG}" 2>/dev/null; then
	echo "CONFIG_NET_SCH_FQ=y" >> "${KERNEL_CFG}"
	echo "Set CONFIG_NET_SCH_FQ=y in ${KERNEL_CFG}"
fi

# Runtime debugging: expose the final kernel config through /proc/config.gz.
# Some upstream targets ignore the seed .config symbols unless they are also
# present in the target kernel config fragment.
for symbol in CONFIG_IKCONFIG CONFIG_IKCONFIG_PROC; do
	if ! grep -q "^${symbol}=" "${KERNEL_CFG}" 2>/dev/null; then
		echo "${symbol}=y" >> "${KERNEL_CFG}"
		echo "Set ${symbol}=y in ${KERNEL_CFG}"
	fi
done

if [ "${INCLUDE_HOMEPROXY:-1}" != "1" ]; then
	echo "========== Skip HomeProxy and sing-box for this build variant =========="
	exit 0
fi

echo "========== Use pinned VIKINGYFY HomeProxy and sing-box =========="
# HomeProxy and sing-box both come from the pinned VIKINGYFY/packages feed.
# Remove stale sources from earlier layouts and drop the duplicate packages
# provided by other feeds so the build scans exactly one variant of each.
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

# feeds install normally creates these symlinks; recreate them defensively so
# duplicate package-name resolution stays deterministic.
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
