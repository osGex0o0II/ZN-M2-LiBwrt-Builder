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

DTS_FILE="target/linux/qualcommax/dts/ipq6000-m2.dts"
LEDS_FILE="target/linux/qualcommax/ipq60xx/base-files/etc/board.d/01_leds"
QUALCOMMAX_MAKEFILE="target/linux/qualcommax/Makefile"
IPQ60XX_TARGET_MAKEFILE="target/linux/qualcommax/ipq60xx/target.mk"

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
kmod-qca-nss-drv-vlan-mgr
kmod-qca-nss-drv-vxlanmgr
kmod-qca-nss-drv-wifi-meshmgr
"

ZN_M2_256M_DEFAULT_PACKAGE_EXCLUDES="
automount
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
		echo "Filtered ipq60xx default packages:${filter_args}"
	fi
}

patch_zn_m2_wired_only_hardware
patch_qualcommax_default_packages

# 1G 改版带板载 USB 3.0 接口，可通过 ENABLE_USB_DATA=1 保留数据功能。
# 256M 原厂无物理 USB 接口，默认仍禁用控制器和 PHY，减少无用硬件初始化。
if [ "${ENABLE_USB_DATA:-0}" = "1" ]; then
	echo "========== Keep ZN-M2 USB controllers enabled =========="
	require_zn_m2_dts_file
	if ! grep -q 'USB_ENABLED_BY_BUILDER' target/linux/qualcommax/dts/ipq6000-m2.dts 2>/dev/null; then
		cp target/linux/qualcommax/dts/ipq6000-m2.dts target/linux/qualcommax/dts/ipq6000-m2.dts.bak
		echo "Backed up DTS to ipq6000-m2.dts.bak"
		cat >> target/linux/qualcommax/dts/ipq6000-m2.dts << 'DTSEND'

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
	if ! grep -q 'USB_DISABLED_BY_BUILDER' target/linux/qualcommax/dts/ipq6000-m2.dts 2>/dev/null; then
		cp target/linux/qualcommax/dts/ipq6000-m2.dts target/linux/qualcommax/dts/ipq6000-m2.dts.bak
		echo "Backed up DTS to ipq6000-m2.dts.bak"
		cat >> target/linux/qualcommax/dts/ipq6000-m2.dts << 'DTSEND'

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
AURORA_COMMIT="${AURORA_COMMIT:-72a10dc3e865fbbc9d30bbb88c9e80439bf4b5ff}"
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
  echo "========== Skip HomeProxy for this build variant =========="
  exit 0
fi

echo "========== Replace HomeProxy and sing-box =========="
rm -rf \
  feeds/luci/applications/luci-app-homeproxy \
  package/feeds/luci/luci-app-homeproxy \
  package/luci-app-homeproxy \
  package/network/services/sing-box

# Pin to a known-good commit for reproducible builds.
# Updated automatically by .github/workflows/auto-update-pinned-deps.yml.
# Use fetch+checkout instead of shallow clone+checkout: --depth=1 only fetches
# the branch tip, so checkout would fail if the pinned hash is not the tip.
HOMEPROXY_COMMIT="${HOMEPROXY_COMMIT:-46137662e2604f7127f9382d834326579db8fb6a}"
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "HOMEPROXY_COMMIT=${HOMEPROXY_COMMIT}" >> "$GITHUB_ENV"
fi
# SHA256 校验基准值：此 hash 对应 HOMEPROXY_COMMIT 状态下 Makefile 的摘要。
# 自动更新 HOMEPROXY_COMMIT 时会同步更新此 hash。
HOMEPROXY_MAKEFILE_SHA256="${HOMEPROXY_MAKEFILE_SHA256:-6700e5b519ca151657f3c8b67d2f067d4f45bb91337a43ca583e6386cb8d0792}"
git clone https://github.com/immortalwrt/homeproxy package/luci-app-homeproxy
cd package/luci-app-homeproxy
git -c advice.detachedHead=false checkout "$HOMEPROXY_COMMIT"

BUILDER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOMEPROXY_PATCH_DIR="$BUILDER_ROOT/patches/homeproxy"
if [ ! -d "$HOMEPROXY_PATCH_DIR" ]; then
  echo "ERROR: HomeProxy patch directory not found: ${HOMEPROXY_PATCH_DIR}" >&2
  exit 1
fi
for patch_file in "$HOMEPROXY_PATCH_DIR"/*.patch; do
  [ -e "$patch_file" ] || continue
  echo "Applying HomeProxy patch: $(basename "$patch_file")"
  git apply "$patch_file"
done

if grep -Eq '^[[:space:]]*sniff: true,|sniff_override_destination' \
  root/etc/homeproxy/scripts/generate_client.uc; then
  echo "ERROR: HomeProxy client generator still contains sing-box 1.13 removed inbound fields." >&2
  exit 1
fi

if sed -n '/function generate_outbound(node)/,/^function get_outbound/p' \
  root/etc/homeproxy/scripts/generate_client.uc |
  grep -Eq '^[[:space:]]*override_address: node\.override_address,|^[[:space:]]*override_port: strToInt\(node\.override_port\),'; then
  echo "ERROR: HomeProxy direct outbound still contains sing-box 1.13 removed override fields." >&2
  exit 1
fi

# 完整性验证：对关键文件 Makefile 做 SHA256 校验，防止拉取到篡改代码
COMPUTED_SHA256="$(sha256sum Makefile 2>/dev/null | awk '{print $1}')"
if [ "$COMPUTED_SHA256" != "$HOMEPROXY_MAKEFILE_SHA256" ]; then
  echo "ERROR: HomeProxy Makefile SHA256 mismatch!" >&2
  echo "  Expected: ${HOMEPROXY_MAKEFILE_SHA256}" >&2
  echo "  Got:      ${COMPUTED_SHA256:-<file not found>}" >&2
  echo "  This may indicate code tampering or HOMEPROXY_COMMIT needs updating." >&2
  exit 1
fi
echo "HomeProxy Makefile integrity verified (SHA256 match)"
cd "$OLDPWD" || exit 1

echo "========== Pin sing-box stable release =========="
SING_BOX_VERSION="${SING_BOX_VERSION:-}"
SING_BOX_HASH="${SING_BOX_HASH:-}"
if [ -z "$SING_BOX_VERSION" ] || [ -z "$SING_BOX_HASH" ]; then
	echo "ERROR: Missing SING_BOX_VERSION or SING_BOX_HASH in pinned deps" >&2
	exit 1
fi

rm -rf package/feeds/packages/sing-box package/feeds/packages/sing-box-tiny
mkdir -p package/network/services/sing-box/files
cat > package/network/services/sing-box/Makefile <<'EOF'
include $(TOPDIR)/rules.mk

PKG_NAME:=sing-box
PKG_VERSION:=__SING_BOX_VERSION__
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/SagerNet/sing-box/tar.gz/v$(PKG_VERSION)?
PKG_HASH:=__SING_BOX_HASH__

PKG_LICENSE:=GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Van Waholtz <brvphoenix@gmail.com>
PKG_CPE_ID:=cpe:/a:sagernet:sing-box

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/sagernet/sing-box
GO_PKG_BUILD_PKG:=$(GO_PKG)/cmd/sing-box
GO_PKG_LDFLAGS_X:=$(GO_PKG)/constant.Version=$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/sing-box-default
  TITLE:=The universal proxy platform
  SECTION:=net
  CATEGORY:=Network
  URL:=https://sing-box.sagernet.org
  DEPENDS:=$(GO_ARCH_DEPENDS) +ca-bundle +kmod-inet-diag +kmod-tun
  USERID:=sing-box=5566:sing-box=5566
endef

define Package/sing-box
  $(Package/sing-box-default)
  TITLE+= (full)
  VARIANT:=full
  DEFAULT_VARIANT:=1
endef

define Package/sing-box/description
  Sing-box is a universal proxy platform which supports hysteria, SOCKS, Shadowsocks,
  ShadowTLS, Tor, trojan, VLess, VMess, WireGuard and so on.
endef

define Package/sing-box-tiny
  $(Package/sing-box-default)
  TITLE+= (tiny)
  PROVIDES:=sing-box
  VARIANT:=tiny
  CONFLICTS:=sing-box
endef

Package/sing-box-tiny/description:=$(Package/sing-box/description)

define Package/sing-box/config
	menu "Select build options"
		depends on PACKAGE_sing-box

		config SINGBOX_WITH_ACME
			bool "Build with ACME TLS certificate issuer support"

		config SINGBOX_WITH_CLASH_API
			bool "Build with Clash API support"
			default y

		config SINGBOX_WITH_DHCP
			bool "Build with DHCP support, see DHCP DNS transport."

		config SINGBOX_WITH_EMBEDDED_TOR
			bool "Build with embedded Tor support"

		config SINGBOX_WITH_GRPC
			bool "Build with standard gRPC support"

		config SINGBOX_WITH_GVISOR
			bool "Build with gVisor support"
			default y

		config SINGBOX_WITH_QUIC
			bool "Build with QUIC support"
			default y

		config SINGBOX_WITH_TAILSCALE
			bool "Build with Tailscale support"
			default y

		config SINGBOX_WITH_UTLS
			bool "Build with uTLS support for TLS outbound"
			default y

		config SINGBOX_WITH_V2RAY_API
			bool "Build with V2Ray API support"

		config SINGBOX_WITH_WIREGUARD
			bool "Build with WireGuard support"
			default y
	endmenu
endef

PKG_CONFIG_DEPENDS:= \
	CONFIG_SINGBOX_WITH_ACME \
	CONFIG_SINGBOX_WITH_CLASH_API \
	CONFIG_SINGBOX_WITH_DHCP \
	CONFIG_SINGBOX_WITH_EMBEDDED_TOR \
	CONFIG_SINGBOX_WITH_GRPC \
	CONFIG_SINGBOX_WITH_GVISOR \
	CONFIG_SINGBOX_WITH_QUIC \
	CONFIG_SINGBOX_WITH_TAILSCALE \
	CONFIG_SINGBOX_WITH_UTLS \
	CONFIG_SINGBOX_WITH_V2RAY_API \
	CONFIG_SINGBOX_WITH_WIREGUARD

ifeq ($(BUILD_VARIANT),tiny)
ifeq ($(CONFIG_SMALL_FLASH),)
GO_PKG_TAGS:=with_gvisor
endif
GO_PKG_TAGS:=$(GO_PKG_TAGS),with_quic,with_utls,with_clash_api
else
GO_PKG_TAGS:=$(subst $(space),$(comma),$(strip \
	$(if $(CONFIG_SINGBOX_WITH_ACME),with_acme) \
	$(if $(CONFIG_SINGBOX_WITH_CLASH_API),with_clash_api) \
	$(if $(CONFIG_SINGBOX_WITH_DHCP),with_dhcp) \
	$(if $(CONFIG_SINGBOX_WITH_EMBEDDED_TOR),with_embedded_tor) \
	$(if $(CONFIG_SINGBOX_WITH_GRPC),with_grpc) \
	$(if $(CONFIG_SINGBOX_WITH_GVISOR),with_gvisor) \
	$(if $(CONFIG_SINGBOX_WITH_QUIC),with_quic) \
	$(if $(CONFIG_SINGBOX_WITH_TAILSCALE),with_tailscale) \
	$(if $(CONFIG_SINGBOX_WITH_UTLS),with_utls) \
	$(if $(CONFIG_SINGBOX_WITH_V2RAY_API),with_v2ray_api) \
	$(if $(CONFIG_SINGBOX_WITH_WIREGUARD),with_wireguard) \
))
endif

define Package/sing-box/conffiles
/etc/config/sing-box
/etc/sing-box/
endef

Package/sing-box-tiny/conffiles=$(Package/sing-box/conffiles)

define Package/sing-box/install
	$(INSTALL_DIR) $(1)/usr/bin/
	$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/sing-box $(1)/usr/bin/sing-box

	$(INSTALL_DIR) $(1)/etc/sing-box
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/release/config/config.json $(1)/etc/sing-box

	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_CONF) ./files/sing-box.conf $(1)/etc/config/sing-box
	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) ./files/sing-box.init $(1)/etc/init.d/sing-box
endef

Package/sing-box-tiny/install=$(Package/sing-box/install)

$(eval $(call BuildPackage,sing-box))
$(eval $(call BuildPackage,sing-box-tiny))
EOF
sed -i \
	-e "s/__SING_BOX_VERSION__/${SING_BOX_VERSION}/g" \
	-e "s/__SING_BOX_HASH__/${SING_BOX_HASH}/g" \
	package/network/services/sing-box/Makefile

cat > package/network/services/sing-box/files/sing-box.conf <<'EOF'
config sing-box 'main'
	option enabled '0'
	option user 'sing-box'
	option conffile '/etc/sing-box/config.json'
	option workdir '/usr/share/sing-box'
#	list ifaces 'wan'
#	list ifaces 'wan6'
EOF
cat > package/network/services/sing-box/files/sing-box.init <<'EOF'
#!/bin/sh /etc/rc.common

USE_PROCD=1
START=99

script=$(readlink "$initscript")
NAME="$(basename ${script:-$initscript})"
PROG="/usr/bin/sing-box"

start_service() {
	config_load "$NAME"

	local enabled user group conffile workdir ifaces
	config_get_bool enabled "main" "enabled" "0"
	[ "$enabled" -eq "1" ] || return 0

	config_get user "main" "user" "root"
	config_get conffile "main" "conffile"
	config_get ifaces "main" "ifaces"
	config_get workdir "main" "workdir" "/usr/share/sing-box"

	mkdir -p "$workdir"
	local group="$(id -ng $user)"
	chown $user:$group "$workdir"

	procd_open_instance "$NAME.main"
	procd_set_param command "$PROG" run -c "$conffile" -D "$workdir"

	# Use root user if you want to use the TUN mode.
	procd_set_param user "$user"
	procd_set_param file "$conffile"
	[ -z "$ifaces" ] || procd_set_param netdev $ifaces
	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_set_param respawn

	procd_close_instance
}

service_triggers() {
	local ifaces
	config_load "$NAME"
	config_get ifaces "main" "ifaces"
	procd_open_trigger
	for iface in $ifaces; do
		procd_add_interface_trigger "interface.*.up" $iface /etc/init.d/$NAME restart
	done
	procd_close_trigger
	procd_add_reload_trigger "$NAME"
}
EOF

echo "========== Custom package sources ready =========="
