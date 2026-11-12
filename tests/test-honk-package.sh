#!/usr/bin/env bash
#
# Contract tests for the vendored honk package and the kernel options it needs.
#
# honk is alpha and its failure modes are expensive to discover on the device:
# a missing BTF section means the engine refuses to start, a missing cgroup BPF
# hook means it aborts during startup, and a leftover HomeProxy package means
# two engines fight over dae0/daens. All of that is decided at build time, so
# the contracts are pinned here.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }

MAKEFILE="$root/package/honk/Makefile"
INIT="$root/package/honk/files/honk.init"
UCI="$root/package/honk/files/honk.config"
CONFIG="$root/package/honk/files/config.dae"
STAGER="$root/scripts/zn-m2-honk-package.sh"

for f in "$MAKEFILE" "$INIT" "$UCI" "$CONFIG" "$STAGER"; do
	[ -f "$f" ] || fail "missing $f"
done

# --- the pinned release asset ---------------------------------------------
grep -Fq 'PKG_VERSION:=0.1.0_beta6' "$MAKEFILE" || fail 'honk version pin drifted'
grep -Fq 'HONK_ASSET_VERSION:=0.1.0-beta.6' "$MAKEFILE" ||
	fail 'honk asset version pin drifted'
grep -Fq 'honk-core-v$(HONK_ASSET_VERSION)-aarch64-unknown-linux-musl-stock-full.tar.gz' "$MAKEFILE" ||
	fail 'honk must use the aarch64 stock-full asset'
grep -Fq 'PKG_HASH:=d07e51a5c5c6b1cc734c096a48beb3c6a5e31816661047b8b49d3ac03a85dcc4' "$MAKEFILE" ||
	fail 'honk asset hash is not the audited one'
if grep -Eq '^PKG_SOURCE:=.*jemalloc' "$MAKEFILE"; then
	fail 'honk must not select the jemalloc variant on a 200 MB device'
fi

# The binary is static; pulling libstdcpp in would only add weight.
if grep -Eq '^\s*DEPENDS.*libstdcpp' "$MAKEFILE"; then
	fail 'honk must not depend on libstdcpp: the release binary is static'
fi
# vmlinux-btf only installs on the exact kernel release it was built for.
if grep -Eq '^\s*DEPENDS.*vmlinux-btf' "$MAKEFILE"; then
	fail 'honk must not depend on vmlinux-btf: this kernel compiles its own BTF'
fi
for dep in kmod-veth kmod-sched-core kmod-sched-bpf kmod-nft-queue \
	kmod-nfnetlink-queue v2ray-geoip v2ray-geosite; do
	grep -Fq "+$dep" "$MAKEFILE" || fail "honk is missing its $dep dependency"
done

# --- the installed file set ------------------------------------------------
for line in \
	'$(INSTALL_BIN) $(PKG_BUILD_DIR)/honk-core $(1)/usr/bin/honk-core' \
	'$(INSTALL_BIN) $(PKG_DIR)/files/honk.init $(1)/etc/init.d/honk' \
	'$(INSTALL_CONF) $(PKG_DIR)/files/honk.config $(1)/etc/config/honk' \
	'$(INSTALL_CONF) $(PKG_DIR)/files/config.dae $(1)/etc/honk/config.dae' \
	"printf '%s\\n' '/etc/honk/data/'" ; do
	grep -Fq -- "$line" "$MAKEFILE" || fail "honk install rule is missing: $line"
done
grep -Fq '$(LN) ../v2ray/geoip.dat $(1)/usr/share/honk/geoip.dat' "$MAKEFILE" ||
	fail 'honk does not link the geoip dataset'
grep -Fq '$(LN) ../v2ray/geosite.dat $(1)/usr/share/honk/geosite.dat' "$MAKEFILE" ||
	fail 'honk does not link the geosite dataset'
# The engine ships disabled: honk#456 can cut LAN access to the router itself,
# so enabling must be a deliberate act, not a side effect of flashing.
if grep -Fq '$(1)/etc/rc.d' "$MAKEFILE"; then
	fail 'honk must not install an rc.d link: the service ships disabled'
fi

# --- the runtime configuration --------------------------------------------
grep -Fq "option store 'file'" "$UCI" ||
	fail 'honk must use the file store: the SQLite store costs resident memory'
grep -Fq "option config_file '/etc/honk/config.dae'" "$UCI" ||
	fail 'honk config path drifted'
grep -Fq "option data_dir '/etc/honk/data'" "$UCI" ||
	fail 'honk data_dir must match the directory sysupgrade keeps'

grep -Fq "local: 'udp://223.5.5.5:53'" "$CONFIG" ||
	fail "honk's own DNS must not loop back into dnsmasq"
if grep -Fq "local: 'udp://127.0.0.1:53'" "$CONFIG"; then
	fail 'honk DNS upstream must not be dnsmasq itself'
fi
grep -Fq 'pname(dnsmasq)' "$CONFIG" ||
	fail 'dnsmasq egress must bypass the proxy engine'
grep -Fq "lan_interface: br-lan" "$CONFIG" || fail 'honk must hook the LAN bridge'
grep -Fq "wan_interface: auto" "$CONFIG" || fail 'honk must follow the default route for WAN'
grep -Fq 'fallback: direct' "$CONFIG" ||
	fail 'honk must start in full-direct mode so enabling it cannot break routing'
grep -Fq 'auto_config_kernel_parameter: true' "$CONFIG" ||
	fail 'honk must configure ip_forward and rp_filter itself'
grep -Fq 'nfqueue_enable: false' "$CONFIG" ||
	fail 'honk NFQUEUE staging must stay off: it starves dnsmasq on 6.12'
if grep -Fq 'nfqueue_enable: true' "$CONFIG"; then
	fail 'nfqueue_enable: true breaks DNS on this kernel'
fi
grep -Fq 'ui: ' "$CONFIG" || fail 'honk must serve a UI'
grep -Fq "'embedded'" "$CONFIG" || fail 'honk must serve the embedded doona build'
grep -Fq 'listen: ' "$CONFIG" || fail 'honk native API listener is missing'
grep -Fq "'0.0.0.0:9527'" "$CONFIG" || fail 'honk native API port drifted'
# doona talks to the native API only; a Clash API listener would be dead weight.
if grep -Eq '^[[:space:]]*clash_api[[:space:]]*\{' "$CONFIG"; then
	fail 'honk must not enable the Clash API: doona uses the native API'
fi
grep -Fq "log_level: warning" "$CONFIG" ||
	fail 'honk must log at warning level to spare the 200 MB device'

# --- the init script ------------------------------------------------------
grep -Fq 'USE_PROCD=1' "$INIT" || fail 'honk init script must use procd'
grep -Fq 'START=99' "$INIT" || fail 'honk must start after the network'
grep -Fq '/sys/kernel/btf/vmlinux' "$INIT" ||
	fail 'honk init script must fail closed when the kernel has no BTF'
grep -Fq 'mount -t bpf bpf /sys/fs/bpf' "$INIT" ||
	fail 'honk init script must mount bpffs'
grep -Fq 'cgroup.subtree_control' "$INIT" ||
	fail 'honk init script must enable the cgroup memory controller'
grep -Fq 'procd_set_param respawn' "$INIT" ||
	fail 'honk must be respawned: issue #476 exits on config reload'
grep -Fq 'dae is running' "$INIT" ||
	fail 'honk init script must refuse to run beside dae'

# --- the staging contract -------------------------------------------------
for symbol in CONFIG_KERNEL_DEBUG_INFO CONFIG_KERNEL_DEBUG_INFO_BTF \
	CONFIG_KERNEL_CGROUPS CONFIG_KERNEL_CGROUP_BPF; do
	grep -Fq "$symbol" "$STAGER" || fail "the staging check must assert $symbol"
done
grep -Fq 'CONFIG_KERNEL_DEBUG_INFO_REDUCED' "$STAGER" ||
	fail 'the staging check must assert DEBUG_INFO_REDUCED is off'
grep -Fq 'vmlinux-btf must not be selected' "$STAGER" ||
	fail 'the staging check must reject vmlinux-btf'
grep -Fq 'legacy proxy package still selected' "$STAGER" ||
	fail 'the staging check must reject the leftover HomeProxy stack'

# --- the three honk profiles ----------------------------------------------
for profile in libwrt-25.12-nss immortalwrt-viking-owrt-ppe immortalwrt-viking-main-nss; do
	grep -Fxq 'SOFTWARE_POLICY=honk-doona' "$root/profiles/$profile.conf" ||
		fail "$profile is not on the honk software policy"
done
# LEDE cannot enable BTF on qualcommax and has no Rust cross toolchain, so it
# must stay on HomeProxy rather than silently losing its proxy stack.
grep -Fxq 'SOFTWARE_POLICY=aurora-homeproxy' "$root/profiles/lede-master-nss.conf" ||
	fail 'LEDE must stay on the HomeProxy policy'
grep -Fxq 'SOFTWARE_POLICY=upstream-native' "$root/profiles/fanchmwrt-25.12.conf" ||
	fail 'FanchmWrt must stay on the upstream-native policy'

# --- the three configs ----------------------------------------------------
for cfg in configs/zn-m2-libwrt-6.12-nss.config \
	configs/zn-m2-immortalwrt-6.18.config \
	configs/zn-m2-immortalwrt-viking-main-nss.config; do
	for symbol in CONFIG_KERNEL_DEBUG_INFO=y \
		CONFIG_KERNEL_DEBUG_INFO_BTF=y \
		CONFIG_KERNEL_CGROUPS=y \
		CONFIG_KERNEL_CGROUP_BPF=y; do
		grep -Fxq "$symbol" "$root/$cfg" || fail "$cfg is missing $symbol"
	done
	grep -Fxq '# CONFIG_KERNEL_DEBUG_INFO_REDUCED is not set' "$root/$cfg" ||
		fail "$cfg must disable KERNEL_DEBUG_INFO_REDUCED or BTF is dropped"
	for package in honk v2ray-geoip v2ray-geosite; do
		grep -Fxq "CONFIG_PACKAGE_${package}=y" "$root/$cfg" ||
			fail "$cfg is missing CONFIG_PACKAGE_${package}=y"
	done
	for package in luci-app-homeproxy sing-box; do
		if grep -Fxq "CONFIG_PACKAGE_${package}=y" "$root/$cfg"; then
			fail "$cfg still selects the legacy proxy package ${package}"
		fi
	done
done

# LEDE keeps the old stack, so its config must not be converted.
if grep -Fq 'CONFIG_PACKAGE_honk=y' "$root/configs/zn-m2-lede-master-nss.config"; then
	fail 'the LEDE config must not select honk'
fi

# --- healthcheck ----------------------------------------------------------
grep -Fq 'pidof honk-core' "$root/files/usr/sbin/zn-m2-healthcheck" ||
	fail 'the healthcheck must watch the honk-core process'
grep -Fq 'restart_service honk' "$root/files/usr/sbin/zn-m2-healthcheck" ||
	fail 'the healthcheck must be able to restart honk'

# --- release notes --------------------------------------------------------
for profile in libwrt-25.12-nss immortalwrt-viking-owrt-ppe immortalwrt-viking-main-nss; do
	out=$(bash "$root/scripts/release-notes.sh" "$profile")
	case "$out" in
		*'doona'*) ;;
		*) fail "$profile release notes do not mention doona" ;;
	esac
	case "$out" in
		*'9527'*) ;;
		*) fail "$profile release notes do not name the doona port" ;;
	esac
	case "$out" in
		*'HomeProxy'*) fail "$profile release notes still mention HomeProxy" ;;
	esac
done

grep -Fq 'luci-app-honk.json' "$MAKEFILE" ||
	fail 'honk installs no LuCI menu entry'
grep -Fq 'overview.js' "$MAKEFILE" ||
	fail 'honk installs no LuCI status view'
grep -Fq '$(1)/usr/share/rpcd/acl.d' "$MAKEFILE" ||
	fail 'honk installs no rpcd ACL'
# The menu must exist even though doona is the real dashboard: without it the
# proxy is invisible in LuCI and looks missing.
[ -f "$root/package/honk/files/luci/menu.d/luci-app-honk.json" ] ||
	fail 'missing the LuCI menu declaration'
[ -f "$root/package/honk/files/luci/acl.d/luci-app-honk.json" ] ||
	fail 'missing the rpcd ACL declaration'
[ -f "$root/package/honk/files/luci/view/honk/overview.js" ] ||
	fail 'missing the LuCI overview view'

echo 'PASS: honk package, kernel prerequisites and software policy contracts'
