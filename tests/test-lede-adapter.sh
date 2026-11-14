#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
source_tree=${1:-$repo/.omo/sources/lede-master}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"; rm -f "$fixture.before" "$fixture.after"' EXIT
mkdir -p "$fixture/target/linux"
cp -R "$source_tree/target/linux/qualcommax" "$fixture/target/linux/"
mkdir -p "$fixture/package/qca"
cp -R "$source_tree/package/qca/qca-mcs" "$fixture/package/qca/"
# The adapter follows KERNEL_PATCHVER, so the fixture must advertise a kernel it
# has a layout patch for. Pin it to 6.12 so this test does not silently start
# exercising a different kernel when upstream flips the default again.
kernel_mk="$fixture/target/linux/qualcommax/Makefile"
if grep -q '^KERNEL_PATCHVER:=' "$kernel_mk"; then
  sed -i 's/^KERNEL_PATCHVER:=.*/KERNEL_PATCHVER:=6.12/' "$kernel_mk"
else
  printf 'KERNEL_PATCHVER:=6.12\n' >> "$kernel_mk"
fi
bash "$repo/adapters/lede-master-nss.sh" "$fixture"
find "$fixture" -type f -exec sha256sum {} + | sort > "$fixture.before"
bash "$repo/adapters/lede-master-nss.sh" "$fixture"
find "$fixture" -type f -exec sha256sum {} + | sort > "$fixture.after"
cmp "$fixture.before" "$fixture.after"
rm "$fixture.before" "$fixture.after"
# The sole image-definition change must be the native ZN-M2 package exclusion.
image="$fixture/target/linux/qualcommax/image/ipq60xx.mk"
grep -q 'DEVICE_PACKAGES += -kmod-ath11k-ahb -wpad-openssl -kmod-usb3 -kmod-usb-dwc3 -kmod-usb-dwc3-qcom' "$image"
diff -u "$source_tree/target/linux/qualcommax/image/ipq60xx.mk" <(sed '/DEVICE_PACKAGES += -kmod-ath11k-ahb -wpad-openssl -kmod-usb3 -kmod-usb-dwc3 -kmod-usb-dwc3-qcom/d' "$image")
network="$fixture/target/linux/qualcommax/ipq60xx/base-files/etc/board.d/02_network"
leds="$fixture/target/linux/qualcommax/ipq60xx/base-files/etc/board.d/01_leds"
platform="$fixture/target/linux/qualcommax/ipq60xx/base-files/lib/upgrade/platform.sh"
source <(sed '/^\. /d;/^board_config_update/,$d' "$network")
ucidef_set_interfaces_lan_wan() { printf '%s|%s' "$1" "$2"; }
[[ $(ipq60xx_setup_interfaces zn,m2) == 'lan1 lan2 lan3|wan' ]]
[[ $(ipq60xx_setup_interfaces linksys,mr7350) == 'lan1 lan2 lan3 lan4|wan' ]]
# LEDE names its LEDs "m2:blue:*"; the ImmortalWrt "blue:*" names never bind.
ucidef_set_led_netdev() { printf '%s:%s\n' "$3" "$4"; }
board_config_update() { :; }
board_config_flush() { :; }
board_name() { echo zn,m2; }
[[ $(. <(sed '/^\. /d' "$leds")) == $'m2:blue:lan:br-lan\nm2:blue:wan:wan' ]]
source "$platform"
board_name() { echo "$board"; }
nand_do_upgrade() { echo "nand:${CI_UBIPART:-}:$1"; }
mmc_do_upgrade() { echo "mmc:$1"; }
default_do_upgrade() { echo "default:$1"; }
board=zn,m2
[[ $(platform_do_upgrade image.bin) == 'nand:rootfs:image.bin' ]]
board=jdcloud,re-cs-02
[[ $(platform_do_upgrade image.bin) == 'mmc:image.bin' ]]
board=unknown
[[ $(platform_do_upgrade image.bin) == 'default:image.bin' ]]
cmp "$source_tree/target/linux/qualcommax/dts/ipq6018-nss.dtsi" "$fixture/target/linux/qualcommax/dts/ipq6018-nss.dtsi"
grep -q '0x4ab00000 0x0 0x1000000' "$fixture/target/linux/qualcommax/dts/ipq6018-m2.dts"
# The panel prints phy3 next to WAN, so the shared cmiot labels are swapped.
grep -q '^&dp2 { label = "lan3"; };$' "$fixture/target/linux/qualcommax/dts/ipq6018-m2.dts"
grep -q '^&dp4 { label = "lan1"; };$' "$fixture/target/linux/qualcommax/dts/ipq6018-m2.dts"
if grep -Eq '^&(dp[0-9]+|switch|mdio) \{$' "$fixture/target/linux/qualcommax/dts/ipq6018-m2.dts"; then
    echo 'FAIL: the adapter must not re-bind hardware nodes, only relabel them' >&2
    exit 1
fi
mcs_patch="$fixture/package/qca/qca-mcs/patches/0003-fix-missing-netfilter-prototypes.patch"
cmp "$repo/patches/lede/9999-qca-mcs-netfilter-prototypes.patch" "$mcs_patch"
grep -q '^+#include "mc_netfilter.h"' "$mcs_patch"
# The header still declares the pre-4.3 hook signatures; including it without
# removing them makes the build fail with conflicting types instead.
grep -q '^-unsigned int mc_pre_routing_hook' "$mcs_patch"
grep -q '^-unsigned int mc_forward_hook' "$mcs_patch"
# Linux 6.12 removed asm/unaligned.h; the replacement is linux/unaligned.h.
grep -q '^+#include <linux/unaligned.h>' "$mcs_patch"
grep -q '^ #include <asm/unaligned.h>' "$mcs_patch"
grep -q 'KERNEL_VERSION(6, 12, 0)' "$mcs_patch"
# Linux 6.12 kernel.h no longer pulls linux/version.h, so the guard needs an
# explicit include or LINUX_VERSION_CODE trips -Werror=undef.
grep -q '^+#include <linux/version.h>' "$mcs_patch"
# Kernel 6.12 enables -Wmissing-prototypes, and mc_proc_create_snooper_entry
# is only ever called from mc_snooping.c, so it has to become static.
grep -q '^+static int mc_proc_create_snooper_entry' "$mcs_patch"
# mc_forward.c and mc_ovs.c define the init/exit hooks declared in their own
# headers but never included them, which -Wmissing-prototypes rejects on 6.12.
grep -q '^+#include "mc_forward.h"' "$mcs_patch"
grep -q '^+#include "mc_ovs.h"' "$mcs_patch"
# Linux 6.16 renamed try_to_del_timer_sync(); qca-mcs is frozen in 2023 and
# needs the shim, otherwise mc_netlink.c fails with -Werror=implicit-function-declaration.
mcs_timer_patch="$fixture/package/qca/qca-mcs/patches/0004-fix-timer-delete-sync-try.patch"
cmp "$repo/patches/lede/9999-qca-mcs-timer-delete-sync-try.patch" "$mcs_timer_patch"
grep -q '^+#define try_to_del_timer_sync(timer) timer_delete_sync_try(timer)$' "$mcs_timer_patch"
grep -q '^+#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 16, 0))$' "$mcs_timer_patch"
# An unknown KERNEL_PATCHVER must fail closed: the adapter has a layout patch
# and a body digest for 6.12 and 6.18 only, so a 6.19 tree must be rejected
# rather than silently shipping a netdevice layout that trips BUILD_BUG_ON.
sed -i 's/^KERNEL_PATCHVER:=.*/KERNEL_PATCHVER:=6.19/' "$kernel_mk"
if bash "$repo/adapters/lede-master-nss.sh" "$fixture" 2>/dev/null; then
    echo 'FAIL: adapter accepted an unsupported kernel version'
    exit 1
fi
sed -i 's/^KERNEL_PATCHVER:=.*/KERNEL_PATCHVER:=6.12/' "$kernel_mk"
# Unsupported NSS source and conflicting installation must fail before mutation.
layout="$fixture/target/linux/qualcommax/patches-6.12/9999-netdevice-nss-flags-layout.patch"
for contract in "$layout" "$fixture/target/linux/qualcommax/patches-6.12/0600-2-qca-nss-ecm-support-PPPOE-offload.patch" "$mcs_patch" "$mcs_timer_patch"; do
    cp "$contract" "$fixture.saved"
    printf '\ncorrupt contract\n' >> "$contract"
    find "$fixture" -type f -exec sha256sum {} + | sort > "$fixture.before"
    if bash "$repo/adapters/lede-master-nss.sh" "$fixture"; then exit 1; fi
    find "$fixture" -type f -exec sha256sum {} + | sort > "$fixture.after"
    cmp "$fixture.before" "$fixture.after"
    mv "$fixture.saved" "$contract"
done
sed -i 's/0x2800000/0x2700000/' "$fixture/target/linux/qualcommax/dts/ipq6018-256m.dtsi"
if PYTHONOPTIMIZE=1 bash "$repo/adapters/lede-master-nss.sh" "$fixture"; then
    echo 'FAIL: optimized Python accepted unexpected Q6 layout'
    exit 1
fi
rm "$fixture/target/linux/qualcommax/dts/ipq6018-256m.dtsi"
if bash "$repo/adapters/lede-master-nss.sh" "$fixture"; then exit 1; fi
echo 'PASS: network, NAND/MMC/default dispatch, Q6, unchanged NSS, idempotence, fail-closed'