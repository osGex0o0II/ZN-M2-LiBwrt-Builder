#!/usr/bin/env bash
# The FanchmWrt fork labels phy0 as lan1 and phy3 as lan3, but the ZN-M2 panel
# prints phy3 next to WAN. The adapter may only swap those two label strings.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
tree=${1:?usage: test-fanch-port-order.sh FORK_SOURCE}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/target/linux"
cp -R "$tree/target/linux/qualcommax" "$fixture/target/linux/"
cp -R "$tree/tests" "$fixture/tests"

dts="$fixture/target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6000-zn-m2.dts"
before=$(sha256sum < "$dts")

bash "$repo/adapters/fanchmwrt-25.12.sh" "$fixture" >/dev/null

# Only the two labels may change; phy-handle, qcom,id and the switch bitmaps
# must stay byte-identical or the hardware binding would move with the name.
diff -u <(grep -E 'phy-handle|qcom,id|switch_(lan|wan)_bmp|port_id|phy_address|reg = <' "$dts") \
	<(grep -E 'phy-handle|qcom,id|switch_(lan|wan)_bmp|port_id|phy_address|reg = <' \
		"$tree/target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6000-zn-m2.dts")

# The override block must be appended and must keep the original label lines.
grep -Fq '/* ZN-M2_PANEL_PORT_ORDER' "$dts"
grep -Fxq '&dp1 { label = "lan3"; };' "$dts"
grep -Fxq '&dp4 { label = "lan1"; };' "$dts"

# Second run must be a no-op, otherwise a repeated prepare flips the labels back.
bash "$repo/adapters/fanchmwrt-25.12.sh" "$fixture" >/dev/null
after=$(sha256sum < "$dts")
[ "$before" != "$after" ]
once=$(sha256sum < "$dts")
bash "$repo/adapters/fanchmwrt-25.12.sh" "$fixture" >/dev/null
[ "$once" = "$(sha256sum < "$dts")" ] || {
	echo 'FAIL: the FanchmWrt label alignment is not idempotent' >&2
	exit 1
}

# The fork's own port test must still pass.
bash "$fixture/tests/zn-m2-port.sh" >/dev/null

echo 'PASS: FanchmWrt port labels match the panel, hardware binding untouched'
