#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

UCI_LOG="$TMP_DIR/uci.log"
UCI_FIREWALL_FIXTURE="$TMP_DIR/firewall.show"
export UCI_LOG UCI_FIREWALL_FIXTURE

mkdir -p "$TMP_DIR/bin"

cat > "$TMP_DIR/bin/uci" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$UCI_LOG"

if [ "${1:-}" = "-X" ] && [ "${2:-}" = "show" ] && [ "${3:-}" = "firewall" ]; then
	cat "$UCI_FIREWALL_FIXTURE"
	exit 0
fi

if [ "${1:-}" = "-q" ] && [ "${2:-}" = "get" ]; then
	case "${3:-}" in
		firewall.cfg01.proto) echo icmp ;;
		firewall.cfg01.target) echo ACCEPT ;;
		firewall.cfg01.family) echo ipv4 ;;
		firewall.cfg01.icmp_type) echo echo-request ;;
		firewall.cfg02.proto) echo icmp ;;
		firewall.cfg02.target) echo ACCEPT ;;
		firewall.cfg02.family) echo ipv6 ;;
		firewall.cfg02.icmp_type) echo "130/0 131/0 132/0 143/0" ;;
		firewall.cfg03.proto) echo icmp ;;
		firewall.cfg03.target) echo ACCEPT ;;
		firewall.cfg03.family) echo ipv6 ;;
		firewall.cfg03.icmp_type) echo "echo-request packet-too-big router-advertisement" ;;
		firewall.cfg04.proto) echo icmp ;;
		firewall.cfg04.target) echo ACCEPT ;;
		firewall.cfg04.family) echo ipv6 ;;
		firewall.cfg04.icmp_type) echo "destination-unreachable packet-too-big" ;;
		firewall.cfg05.proto) echo icmp ;;
		firewall.cfg05.target) echo ACCEPT ;;
		firewall.cfg05.family) echo ipv4 ;;
		firewall.cfg05.icmp_type) echo destination-unreachable ;;
		*) exit 1 ;;
	esac
	exit 0
fi

exit 0
MOCK
chmod +x "$TMP_DIR/bin/uci"

cat > "$UCI_FIREWALL_FIXTURE" <<'FIXTURE'
firewall.cfg01.src='wan'
firewall.cfg02.src='wan'
firewall.cfg03.src='wan'
firewall.cfg04.src='wan'
firewall.cfg05.src='wan'
FIXTURE

factory_default_scripts="
files/etc/uci-defaults/98-network-performance.sh
files/etc/uci-defaults/99-set-ui.sh
files-1g/etc/uci-defaults/zz-proxygateway-stability.sh
files-256m/etc/uci-defaults/98-network-performance.sh
files-256m/etc/uci-defaults/99-zram.sh
files-256m/etc/uci-defaults/zz-mainrouter-stability.sh
"

for script in $factory_default_scripts; do
	: > "$UCI_LOG"
	ZN_M2_CONFIG_RESTORED=1 PATH="$TMP_DIR/bin:$PATH" \
		sh "$ROOT_DIR/$script" >/dev/null 2>&1
	if [ -s "$UCI_LOG" ]; then
		echo "FAIL: $script changed UCI state during config restore" >&2
		cat "$UCI_LOG" >&2
		exit 1
	fi
done

# The wired-only LED cleanup is an upgrade migration, not a factory default.
: > "$UCI_LOG"
ZN_M2_CONFIG_RESTORED=1 ZN_M2_BOARD_NAME='zn,m2' PATH="$TMP_DIR/bin:$PATH" \
	sh "$ROOT_DIR/files/etc/uci-defaults/99-set-ui.sh" >/dev/null 2>&1
cat > "$TMP_DIR/expected-migration.log" <<'EOF'
-q delete system.led_wlan2g
-q delete system.led_wlan5g
commit system
EOF
if ! cmp -s "$TMP_DIR/expected-migration.log" "$UCI_LOG"; then
	echo "FAIL: preserved-config migration changed administrator policy" >&2
	diff -u "$TMP_DIR/expected-migration.log" "$UCI_LOG" >&2 || true
	exit 1
fi

if [ -e "$ROOT_DIR/files/etc/uci-defaults/96-root-password.sh" ]; then
	echo "FAIL: public default-password script is still present" >&2
	exit 1
fi
grep -Fq 'remove_blank_root_ssh_patch' "$ROOT_DIR/libwrt.sh"
grep -Fq \
	'DROPBEAR_BLANK_ROOT_PATCH_SHA256="58d5730b45a51d77e574745b39e4b83c38115d09b80d3d1a590c21adde08f3a3"' \
	"$ROOT_DIR/libwrt.sh"

: > "$UCI_LOG"
PATH="$TMP_DIR/bin:$PATH" sh \
	"$ROOT_DIR/files/etc/uci-defaults/99-set-ui.sh" >/dev/null 2>&1

grep -Fxq -- "-q delete firewall.cfg01" "$UCI_LOG"

for protected_section in cfg02 cfg03 cfg04 cfg05; do
	if grep -Fq -- "-q delete firewall.${protected_section}" "$UCI_LOG"; then
		echo "FAIL: protected ICMP rule firewall.${protected_section} was deleted" >&2
		exit 1
	fi
done

: > "$UCI_LOG"
PATH="$TMP_DIR/bin:$PATH" sh \
	"$ROOT_DIR/files-256m/etc/uci-defaults/98-network-performance.sh" \
	>/dev/null 2>&1

grep -Fxq -- "-q set dhcp.@dnsmasq[0].cachesize=4096" "$UCI_LOG"
grep -Fxq -- "-q delete dhcp.@dnsmasq[0].min_cache_ttl" "$UCI_LOG"
grep -Fxq -- "-q delete dhcp.@dnsmasq[0].allservers" "$UCI_LOG"
grep -Fxq -- "-q delete dhcp.@dnsmasq[0].server" "$UCI_LOG"
if grep -Eq '223\.5\.5\.5|119\.29\.29\.29|add_list.*server' "$UCI_LOG"; then
	echo "FAIL: 256M defaults still force a public DNS server" >&2
	exit 1
fi

grep -Fq "noresolv='0'" \
	"$ROOT_DIR/files-256m/etc/uci-defaults/zz-mainrouter-stability.sh"
grep -Fxq 'net.core.netdev_max_backlog=1000' \
	"$ROOT_DIR/files-256m/etc/sysctl.d/10-bbr.conf"
grep -Fxq 'net.netfilter.nf_conntrack_max=16384' \
		"$ROOT_DIR/files-256m/etc/sysctl.d/zz-conntrack.conf"
if grep -Fq 'net.ecm.front_end_conn_limit' \
	"$ROOT_DIR/files-256m/etc/sysctl.d/zz-conntrack.conf"; then
	echo "FAIL: ECM sysctl is still applied before the module loads" >&2
	exit 1
fi
grep -Fq 'sysctl -w net.ecm.front_end_conn_limit=1' \
	"$ROOT_DIR/patches/qca-nss-ecm/256m-runtime-limits.patch"

CONFIG_256M="$ROOT_DIR/configs/zn-m2-256m-mainrouter.config"
grep -Fxq 'CONFIG_DEVEL=y' "$CONFIG_256M"
grep -Fxq 'CONFIG_CCACHE=y' "$CONFIG_256M"
grep -Fxq 'CONFIG_TARGET_ROOTFS_INITRAMFS=n' "$CONFIG_256M"
grep -Fxq 'CONFIG_NSS_MEM_PROFILE_LOW=y' "$CONFIG_256M"
grep -Fxq '# CONFIG_NSS_MEM_PROFILE_MEDIUM is not set' "$CONFIG_256M"
grep -Fxq '# CONFIG_NSS_MEM_PROFILE_HIGH is not set' "$CONFIG_256M"
if [ "$(grep -Ec '^CONFIG_NSS_MEM_PROFILE_(LOW|MEDIUM|HIGH)=y$' "$CONFIG_256M")" -ne 1 ]; then
	echo "FAIL: 256M config must select exactly one NSS memory profile" >&2
	exit 1
fi

for required_package in ppp ppp-mod-pppoe kmod-ppp kmod-pppoe; do
	grep -Fxq "CONFIG_PACKAGE_${required_package}=y" "$CONFIG_256M"
done
for required_nss in \
	PACKAGE_kmod-qca-nss-drv PACKAGE_kmod-qca-nss-ecm \
	NSS_DRV_BRIDGE_ENABLE NSS_DRV_IGS_ENABLE NSS_DRV_IPV6_ENABLE \
	NSS_DRV_LAG_ENABLE NSS_DRV_PPPOE_ENABLE NSS_DRV_SHAPER_ENABLE \
	NSS_DRV_VIRT_IF_ENABLE NSS_DRV_VLAN_ENABLE; do
	grep -Fxq "CONFIG_${required_nss}=y" "$CONFIG_256M"
done
for excluded_nss in \
	NSS_DRV_CRYPTO_ENABLE NSS_DRV_GRE_ENABLE NSS_DRV_GRE_REDIR_ENABLE \
	NSS_DRV_GRE_TUNNEL_ENABLE NSS_DRV_L2TP_ENABLE NSS_DRV_MAPT_ENABLE \
	NSS_DRV_PPTP_ENABLE NSS_DRV_IPSEC_ENABLE; do
	grep -Fxq "CONFIG_${excluded_nss}=n" "$CONFIG_256M"
done
for excluded_package in \
	shellsync kmod-macvlan kmod-mppe \
	kmod-pptp kmod-pppol2tp kmod-l2tp kmod-l2tp-eth kmod-l2tp-ip \
	kmod-gre kmod-gre6 kmod-qca-nss-crypto nss-eip-firmware \
	e2fsprogs f2fs-tools f2fsck mkf2fs losetup kmod-fs-ext4 kmod-fs-f2fs \
	kmod-leds-pwm kmod-phy-aquantia; do
	grep -Fxq "CONFIG_PACKAGE_${excluded_package}=n" "$CONFIG_256M"
done

CONFIG_1G="$ROOT_DIR/configs/zn-m2-1g-proxygateway.config"
grep -Fxq 'CONFIG_DEVEL=y' "$CONFIG_1G"
grep -Fxq 'CONFIG_CCACHE=y' "$CONFIG_1G"

echo "uci-defaults regression tests passed"
