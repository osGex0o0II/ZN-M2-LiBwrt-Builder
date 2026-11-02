#!/usr/bin/env bash
set -euo pipefail
cd "${1:-.}"
base=target/linux/qualcommax
mem=$base/patches-6.18/0103-arm64-dts-ipq6018-add-reserved-memory-nodes.patch
dts=$base/dts/ipq6000-m2.dts
fail() { echo "ERROR: unsupported Viking layout: $*" >&2; exit 1; }
for file in "$mem" "$dts" "$base/image/ipq60xx.mk" "$base/ipq60xx/target.mk" "$base/Makefile"; do
    test -f "$file" || fail "$file missing"
done
grep -Eq '^\+.*wifi: wifi@' "$base/patches-6.18/0906-arm64-dts-qcom-ipq6018-add-wifi-node.patch" || fail 'wifi declaration missing'
grep -Eq '^\+.*usb3: usb@' "$base/patches-6.18/0144-arm64-dts-qcom-ipq6018-Flatten-usb-controller-nodes.patch" || fail 'USB declaration missing'
test -d package/qca-nss || fail 'built-in NSS packages missing'
grep -q '^KERNEL_PATCHVER:=6.18$' "$base/Makefile" || fail 'kernel changed'
grep -Fq '#include "ipq6000-cmiot.dtsi"' "$dts" || fail 'board include changed'
for label in nss_region q6_region q6_etr_region m3_dump_region ramoops_region; do
    grep -Eq "^\+.*${label}:" "$mem" || fail "$label declaration missing"
done
grep -Fq 'reg = <0x0 0x40000000 0x0 0x1000000>;' "$mem" || fail 'NSS layout changed'
grep -Fq 'q6_region: q6@4ab00000' "$mem" || fail 'Q6 layout changed'
grep -Fq '$(eval $(call BuildTarget))' "$base/Makefile" || fail 'BuildTarget missing'
grep -q '^define Device/zn_m2$' "$base/image/ipq60xx.mk" || fail 'device missing'
if ! grep -q 'ZN_M2_VIKING_NSS_WIRED' "$dts"; then
cat >> "$dts" <<'DTS'

/* ZN_M2_VIKING_NSS_WIRED: Q6 offline, retain NSS firmware reservation. */
&wifi { status = "disabled"; };
&usb3 { status = "disabled"; };
&nss_region { reg = <0x0 0x40000000 0x0 0x1000000>; };
&q6_region { reg = <0x0 0x4ab00000 0x0 0x1000000>; };
&q6_etr_region { reg = <0x0 0x4bb00000 0x0 0x0>; };
&m3_dump_region { reg = <0x0 0x4bc00000 0x0 0x0>; };
&ramoops_region { reg = <0x0 0x4bd00000 0x0 0x100000>; };
DTS
fi
if ! grep -q 'ZN_M2_VIKING_NSS_FILTER' "$base/Makefile"; then
awk '/^\$\(eval \$\(call BuildTarget\)\)/ {print "# ZN_M2_VIKING_NSS_FILTER"; print "DEFAULT_PACKAGES := $(filter-out wpad% kmod-ath% ath11k% kmod-usb% kmod-fs% automount e2fsprogs f2fs-tools losetup,$(DEFAULT_PACKAGES))"} {print}' "$base/Makefile" > "$base/Makefile.tmp"
mv "$base/Makefile.tmp" "$base/Makefile"
fi
sed -i '/^DEFAULT_PACKAGES += ath11k-firmware-ipq6018-ddwrt$/d' "$base/ipq60xx/target.mk"
awk '/^define Device\/zn_m2$/ {board=1} board {gsub(/ipq-wifi-zn_m2/, "")} /^endef$/ {board=0} {print}' "$base/image/ipq60xx.mk" > "$base/image/ipq60xx.mk.tmp"
mv "$base/image/ipq60xx.mk.tmp" "$base/image/ipq60xx.mk"
echo 'Viking main NSS hardware adapter applied'
