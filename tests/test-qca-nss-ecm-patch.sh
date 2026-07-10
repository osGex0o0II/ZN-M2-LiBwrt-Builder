#!/bin/sh
set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
patch_dir="$repo_root/patches/qca-nss-ecm"
feed_dir="${1:-${ECM_FEED_DIR:-}}"

if [ -z "$feed_dir" ] || [ ! -f "$feed_dir/Makefile" ] ||
   [ ! -f "$feed_dir/files/qca-nss-ecm.init" ]; then
	echo "usage: $0 /path/to/nss-packages/qca-nss-ecm" >&2
	exit 2
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT HUP INT TERM
mkdir -p "$workdir/qca-nss-ecm"
cp "$feed_dir/Makefile" "$workdir/qca-nss-ecm/Makefile"
mkdir -p "$workdir/qca-nss-ecm/files"
cp "$feed_dir/files/qca-nss-ecm.init" "$workdir/qca-nss-ecm/files/qca-nss-ecm.init"
git -C "$workdir" init -q
for patch_file in \
	"$patch_dir/firmware-config-depends.patch" \
	"$patch_dir/256m-disable-pptp-l2tp.patch" \
	"$patch_dir/256m-runtime-limits.patch"; do
	git -C "$workdir" apply --check "$patch_file"
	git -C "$workdir" apply "$patch_file"
done

makefile="$workdir/qca-nss-ecm/Makefile"
config_deps="$(sed -n '/^PKG_CONFIG_DEPENDS:=/,/^$/p' "$makefile")"
printf '%s\n' "$config_deps" | grep -Fq 'CONFIG_NSS_FIRMWARE_VERSION_12_5' || {
	echo "missing NSS 12.5 firmware version from ECM PKG_CONFIG_DEPENDS" >&2
	exit 1
}
if grep -Eq 'PACKAGE_kmod-pppoe:kmod-(pptp|pppol2tp)' "$makefile"; then
	echo "ECM still forces a PPTP/L2TP package through PPPoE" >&2
	exit 1
fi

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
	grep -q "$setting" "$makefile" || {
		echo "missing expected ECM setting: $setting" >&2
		exit 1
	}
done

if grep -Eq 'ECM_INTERFACE_(PPTP|L2TPV2|L2TPV2_PPTP|GRE|GRE_TAP|GRE_TUN)_ENABLE=y' "$makefile"; then
	echo "an ECM PPTP/L2TP/GRE tunnel path is still enabled" >&2
	exit 1
fi

ecm_init="$workdir/qca-nss-ecm/files/qca-nss-ecm.init"
modprobe_line="$(grep -n '^[[:space:]]*modprobe ecm$' "$ecm_init" | cut -d: -f1)"
limit_line="$(grep -n 'sysctl -w net.ecm.front_end_conn_limit=1' "$ecm_init" | cut -d: -f1)"
if [ -z "$modprobe_line" ] || [ -z "$limit_line" ] || [ "$limit_line" -le "$modprobe_line" ]; then
	echo "ECM connection limit is not applied after modprobe" >&2
	exit 1
fi
grep -Fq '[ ! -w /proc/sys/net/ecm/front_end_conn_limit ]' "$ecm_init"
grep -Fq 'load_ecm || return 1' "$ecm_init"

# Reverse checks prove the resulting tree contains both exact patches once.
for patch_file in \
	"$patch_dir/256m-runtime-limits.patch" \
	"$patch_dir/256m-disable-pptp-l2tp.patch" \
	"$patch_dir/firmware-config-depends.patch"; do
	git -C "$workdir" apply --reverse --check "$patch_file"
done
echo "qca-nss-ecm 256M patch regression test passed"
