#!/usr/bin/env bash
# Validation only: the source fork owns and versions all board modifications.
set -euo pipefail
tree=${1:?usage: fanchmwrt-25.12.sh SOURCE_ROOT}
base="$tree/target/linux/qualcommax"
dts="$base/files/arch/arm64/boot/dts/qcom/ipq6000-zn-m2.dts"
grep -Fxq 'KERNEL_PATCHVER:=6.12' "$base/Makefile"
grep -Fq 'compatible = "zn,m2", "qcom,ipq6018";' "$dts"
grep -Fq 'define Device/zn_m2' "$base/image/ipq60xx.mk"
grep -Fq 'DEVICE_DTS := ipq6000-zn-m2' "$base/image/ipq60xx.mk"
grep -Fq 'luci-theme-fanchmwrt' "$base/image/ipq60xx.mk"
grep -Fq 'fwxd kmod-fwx' "$base/image/ipq60xx.mk"
grep -Fq '0x4ab00000 0x0 0x1000000' "$dts"
for file in etc/board.d/01_leds etc/board.d/02_network lib/upgrade/platform.sh; do
  grep -Fq 'zn,m2' "$base/ipq60xx/base-files/$file"
done
echo 'Native FanchmWrt ZN-M2 source port present; no board patch applied by builder'
