#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
source_tree=${1:-$repo/.omo/sources/lede-master}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"; rm -f "$fixture.before" "$fixture.after"' EXIT
mkdir -p "$fixture/target/linux"
cp -R "$source_tree/target/linux/qualcommax" "$fixture/target/linux/"
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
platform="$fixture/target/linux/qualcommax/ipq60xx/base-files/lib/upgrade/platform.sh"
source <(sed '/^\. /d;/^board_config_update/,$d' "$network")
ucidef_set_interfaces_lan_wan() { printf '%s|%s' "$1" "$2"; }
[[ $(ipq60xx_setup_interfaces zn,m2) == 'lan1 lan2 lan3|wan' ]]
[[ $(ipq60xx_setup_interfaces linksys,mr7350) == 'lan1 lan2 lan3 lan4|wan' ]]
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
sed -i 's/0x2800000/0x2700000/' "$fixture/target/linux/qualcommax/dts/ipq6018-256m.dtsi"
if PYTHONOPTIMIZE=1 bash "$repo/adapters/lede-master-nss.sh" "$fixture"; then
    echo 'FAIL: optimized Python accepted unexpected Q6 layout'
    exit 1
fi
rm "$fixture/target/linux/qualcommax/dts/ipq6018-256m.dtsi"
if bash "$repo/adapters/lede-master-nss.sh" "$fixture"; then exit 1; fi
echo 'PASS: network, NAND/MMC/default dispatch, Q6, unchanged NSS, idempotence, fail-closed'
