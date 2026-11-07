#!/usr/bin/env bash
# The source fork owns the board definition; the builder only corrects the two
# swapped port labels so the Linux netdev names match the physical panel.
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

# Port labels read the board hierarchy, so the same helper serves both checks
# and the rewrite guard. Only the label strings may change: phy-handle, qcom,id
# and both switch bitmaps must stay untouched or the hardware binding moves.
node_label() {
  awk -v node="&$1 {" '
    $0 == node { inside = 1; next }
    inside && $0 == "};" { exit }
    inside && /label = "/ {
      sub(/.*label = "/, "")
      sub(/";.*/, "")
      print
      exit
    }
  ' "$dts"
}

current_dp1="$(node_label dp1)"
current_dp4="$(node_label dp4)"
marker='ZN-M2_PANEL_PORT_ORDER'

if grep -Fq "$marker" "$dts"; then
  echo 'ZN-M2 port labels already aligned, skip'
  exit 0
fi

if [ "$current_dp1" = 'lan3' ] && [ "$current_dp4" = 'lan1' ]; then
  # The fork fixed the panel order itself; nothing to append.
  echo 'ZN-M2 port labels already match the panel, no override needed'
  exit 0
fi

if [ "$current_dp1" != 'lan1' ] || [ "$current_dp4" != 'lan3' ]; then
  echo "ERROR: unexpected ZN-M2 port labels (dp1=${current_dp1:-none} dp4=${current_dp4:-none}); review the fork before building" >&2
  exit 1
fi

cat >> "$dts" <<'DTS'

/* ZN-M2_PANEL_PORT_ORDER: WAN, LAN1, LAN2, LAN3 from left to right. */
&dp1 { label = "lan3"; };
&dp4 { label = "lan1"; };
DTS
echo 'ZN-M2 port labels aligned with the panel order'
