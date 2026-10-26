#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
WF_618="$ROOT_DIR/.github/workflows/zn-m2-256m-6.18.yml"
CONFIG_618="$ROOT_DIR/configs/zn-m2-immortalwrt-6.18.config"
DEPS_618="$ROOT_DIR/deps/immortalwrt-6.18.env"
LIB_618="$ROOT_DIR/immortalwrt-6.18.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

[ -f "$WF_618" ] || fail "6.18 workflow is missing"
[ -f "$CONFIG_618" ] || fail "6.18 config is missing"
[ -f "$DEPS_618" ] || fail "6.18 pinned dependencies are missing"
[ -f "$LIB_618" ] || fail "6.18 customisation script is missing"

# --- workflow / pin / config contracts -------------------------------------
grep -Fq 'REPO_URL: https://github.com/VIKINGYFY/immortalwrt.git' "$WF_618" ||
	fail "6.18 workflow does not use the ImmortalWrt fork"
grep -Fq 'REPO_BRANCH: owrt' "$WF_618" ||
	fail "6.18 workflow does not use the owrt branch"
grep -Fq 'CONFIG_FILE: configs/zn-m2-immortalwrt-6.18.config' "$WF_618" ||
	fail "6.18 workflow does not use the 6.18 config"
grep -Fq 'DIY_SCRIPT: immortalwrt-6.18.sh' "$WF_618" ||
	fail "6.18 workflow does not use the 6.18 customisation script"
grep -Fq 'PINNED_DEPS_FILE: deps/immortalwrt-6.18.env' "$WF_618" ||
	fail "6.18 workflow does not use the 6.18 pin file"
grep -Fq 'FIRMWARE_TAG: zn-m2-immortalwrt-6.18' "$WF_618" ||
	fail "6.18 firmware tag is not distinct"
grep -Fq 'FIRMWARE_RELEASE: "true"' "$WF_618" ||
	fail "6.18 scheduled builds must publish their own release"
grep -Fq 'schedule:' "$WF_618" ||
	fail "6.18 workflow has no weekly schedule"
grep -Fq 'cron: "0 11 * * 6"' "$WF_618" ||
	fail "6.18 schedule is not staggered from the 6.12 build"
grep -Fq 'pull_request:' "$WF_618" ||
	fail "6.18 workflow does not validate pull requests"
grep -Fq 'tag: v${{ needs.build.outputs.file_version }}-${{ env.FIRMWARE_TAG }}' "$WF_618" ||
	fail "6.18 release tag is not tied to its own firmware tag"
grep -Fq 'RELEASE_TAG_SUFFIX: zn-m2-immortalwrt-6.18' "$WF_618" ||
	fail "6.18 release retention does not use its own suffix"
if grep -Eq 'nss_packages|sqm_scripts_nss|FEED_NSS|FEED_SQM' "$WF_618"; then
	fail "6.18 workflow still feeds the NSS/SQM stack"
fi
grep -Fq 'src-git vikingfy https://github.com/VIKINGYFY/packages.git' "$WF_618" ||
	fail "6.18 workflow does not install the pinned VIKINGYFY feed"
grep -Fq 'ImmortalWrt-${FILE_VERSION}-ZN_M2-NOWIFI-256M-6.18-factory.ubi' "$WF_618" ||
	fail "6.18 factory image name is not distinct"
grep -Fq 'ImmortalWrt-${FILE_VERSION}-ZN_M2-NOWIFI-256M-6.18-sysupgrade.bin' "$WF_618" ||
	fail "6.18 sysupgrade image name is not distinct"

grep -Eq '^OPENWRT_COMMIT=[0-9a-f]{40}$' "$DEPS_618" ||
	fail "6.18 source pin is missing"
grep -Eq '^VIKINGYFY_COMMIT=[0-9a-f]{40}$' "$DEPS_618" ||
	fail "6.18 proxy feed pin is missing"
if grep -Eq '^FEED_(NSS_PACKAGES|SQM_SCRIPTS_NSS)_COMMIT=' "$DEPS_618"; then
	fail "6.18 pin file still contains NSS feed pins"
fi

grep -Fq 'CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_zn_m2=y' "$CONFIG_618" ||
	fail "6.18 config does not select zn_m2"
grep -Fq 'CONFIG_TARGET_DEVICE_PACKAGES_qualcommax_ipq60xx_DEVICE_zn_m2=""' "$CONFIG_618" ||
	fail "6.18 config does not clear the zn_m2 device packages"
grep -Fq 'CONFIG_TARGET_PER_DEVICE_ROOTFS=y' "$CONFIG_618" ||
	fail "6.18 config does not request per-device rootfs"
if grep -Eq '^CONFIG_(IPQ_MEM_PROFILE|NSS_MEM_PROFILE|NSS_DRV|NSS_FIRMWARE)' "$CONFIG_618"; then
	fail "6.18 config contains 6.12-only NSS/memory-profile symbols"
fi
for required in \
	CONFIG_PACKAGE_luci-app-homeproxy=y \
	CONFIG_PACKAGE_sing-box=y \
	CONFIG_PACKAGE_luci-app-gecoosac=y \
	CONFIG_PACKAGE_gecoosac=y \
	CONFIG_PACKAGE_kmod-tun=y \
	CONFIG_PACKAGE_kmod-nft-queue=y; do
	grep -Fxq "$required" "$CONFIG_618" ||
		fail "6.18 config is missing ${required}"
done
for forbidden in \
	CONFIG_PACKAGE_kmod-ath11k=y \
	CONFIG_PACKAGE_ath11k-firmware-ipq6018-ddwrt=y \
	CONFIG_PACKAGE_ipq-wifi-zn_m2=y \
	CONFIG_PACKAGE_wpad-openssl=y \
	CONFIG_PACKAGE_kmod-usb3=y \
	CONFIG_PACKAGE_kmod-usb-storage=y \
	CONFIG_PACKAGE_kmod-fs-ext4=y; do
	if grep -Fxq "$forbidden" "$CONFIG_618"; then
		fail "6.18 config still enables ${forbidden}"
	fi
done

# --- extract the hardware section and run it in a fixture -------------------
# The script's Aurora/HomeProxy half needs network and the cloned feeds; the
# hardware half is self-contained and is what this test exercises.
awk '
	/^echo "========== Inject Aurora theme =========="$/ { exit }
	{ print }
' "$LIB_618" > "$TMP_DIR/hardware.sh"
grep -Fq 'echo "========== Inject Aurora theme =========="' "$LIB_618" ||
	fail "immortalwrt-6.18.sh lost its Aurora section marker"

tree="$TMP_DIR/tree"
mkdir -p \
	"$tree/target/linux/qualcommax/dts" \
	"$tree/target/linux/qualcommax/image" \
	"$tree/target/linux/qualcommax/ipq60xx"
cat > "$tree/target/linux/qualcommax/Makefile" <<'EOF'
KERNEL_PATCHVER:=6.18
DEFAULT_PACKAGES += wpad-openssl kmod-ath11k kmod-usb3 e2fsprogs
$(eval $(call BuildTarget))
EOF
: > "$tree/target/linux/qualcommax/config-6.18"
cat > "$tree/target/linux/qualcommax/dts/ipq6000-m2.dts" <<'EOF'
/dts-v1/;
#include "ipq6000-cmiot.dtsi"
/ { model = "ZN M2 test fixture"; };
&wifi { status = "okay"; };
EOF
cat > "$tree/target/linux/qualcommax/ipq60xx/target.mk" <<'EOF'
SUBTARGET:=ipq60xx
DEFAULT_PACKAGES += ath11k-firmware-ipq6018-ddwrt
EOF
cat > "$tree/target/linux/qualcommax/image/ipq60xx.mk" <<'EOF'
define Device/zn_m2
	$(call Device/nand-common)
	DEVICE_VENDOR := ZN
	DEVICE_MODEL := M2
	SOC := ipq6000
	DEVICE_PACKAGES := ipq-wifi-zn_m2
endef
TARGET_DEVICES += zn_m2
EOF

(
	cd "$tree"
	bash "$TMP_DIR/hardware.sh"
	bash "$TMP_DIR/hardware.sh"
)

DTS_618="$tree/target/linux/qualcommax/dts/ipq6000-m2.dts"
grep -Fq '6.18_WIRED_ONLY_16M' "$DTS_618"
grep -Fq '&wifi { status = "disabled"; };' "$DTS_618"
grep -Fq '&usb3 { status = "disabled"; };' "$DTS_618"
grep -Fq '&nss_region { reg = <0x0 0x40000000 0x0 0x0>; };' "$DTS_618"
grep -Fq 'reg = <0x0 0x4ab00000 0x0 0x1000000>;' "$DTS_618"
[ "$(grep -Fc '6.18_WIRED_ONLY_16M' "$DTS_618")" -eq 1 ] ||
	fail "6.18 hardware patch is not idempotent"

if grep -Fq 'DEFAULT_PACKAGES += ath11k-firmware-ipq6018-ddwrt' \
	"$tree/target/linux/qualcommax/ipq60xx/target.mk"; then
	fail "ath11k firmware default is still present in the 6.18 target"
fi
if awk '/^define Device\/zn_m2$/{f=1} f&&/^endef$/{print;exit} f' \
	"$tree/target/linux/qualcommax/image/ipq60xx.mk" | grep -q 'ipq-wifi-zn_m2'; then
	fail "ipq-wifi-zn_m2 is still part of the 6.18 zn_m2 device packages"
fi
grep -Fxq 'CONFIG_NET_SCH_FQ=y' "$tree/target/linux/qualcommax/config-6.18"
grep -Fxq 'CONFIG_IKCONFIG=y' "$tree/target/linux/qualcommax/config-6.18"
grep -Fxq 'CONFIG_LOG_BUF_SHIFT=18' "$tree/target/linux/qualcommax/config-6.18"
grep -Fq 'ZN_M2_6_18_DEFAULT_PACKAGE_FILTER' \
	"$tree/target/linux/qualcommax/Makefile"
grep -Fq 'filter-out' "$tree/target/linux/qualcommax/Makefile"
grep -Fq 'wpad-openssl' "$tree/target/linux/qualcommax/Makefile"

echo "6.18 contract regression tests passed"
