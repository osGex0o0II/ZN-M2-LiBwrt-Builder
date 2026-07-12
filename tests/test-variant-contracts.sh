#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
LIBWRT="$ROOT_DIR/libwrt.sh"
CONFIG_1G="$ROOT_DIR/configs/zn-m2-1g-proxygateway.config"

full_variant="$(sed -n '/^define Package\/sing-box$/,/^endef$/p' "$LIBWRT")"
tiny_variant="$(sed -n '/^define Package\/sing-box-tiny$/,/^endef$/p' "$LIBWRT")"

printf '%s\n' "$full_variant" | grep -Fxq '  CONFLICTS:=sing-box-tiny'
printf '%s\n' "$tiny_variant" | grep -Fxq '  PROVIDES:=sing-box'
if printf '%s\n' "$tiny_variant" | grep -Fq 'CONFLICTS:=sing-box'; then
	echo "FAIL: sing-box-tiny conflicts with its own provided package" >&2
	exit 1
fi

for setting in \
	CONFIG_TARGET_ROOTFS_INITRAMFS=n \
	CONFIG_IPQ_MEM_PROFILE_1024=y \
	CONFIG_NSS_MEM_PROFILE_MEDIUM=y \
	CONFIG_PACKAGE_kmod-qca-nss-drv=y \
	CONFIG_PACKAGE_kmod-qca-nss-ecm=y \
	CONFIG_NSS_DRV_BRIDGE_ENABLE=y \
	CONFIG_NSS_DRV_IPV6_ENABLE=y \
	CONFIG_NSS_DRV_PPPOE_ENABLE=y \
	CONFIG_NSS_DRV_VLAN_ENABLE=y; do
	grep -Fxq "$setting" "$CONFIG_1G"
done

grep -Fxq '# CONFIG_IPQ_MEM_PROFILE_256 is not set' "$CONFIG_1G"
grep -Fxq '# CONFIG_IPQ_MEM_PROFILE_512 is not set' "$CONFIG_1G"
grep -Fxq '# CONFIG_NSS_MEM_PROFILE_LOW is not set' "$CONFIG_1G"
grep -Fxq '# CONFIG_NSS_MEM_PROFILE_HIGH is not set' "$CONFIG_1G"

[ "$(grep -Ec '^CONFIG_IPQ_MEM_PROFILE_(256|512|1024)=y$' "$CONFIG_1G")" -eq 1 ]
[ "$(grep -Ec '^CONFIG_NSS_MEM_PROFILE_(LOW|MEDIUM|HIGH)=y$' "$CONFIG_1G")" -eq 1 ]

echo "variant contract regression tests passed"
