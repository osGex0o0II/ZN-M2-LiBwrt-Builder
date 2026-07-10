#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

make_fixture() {
	variant="$1"
	tree="$TMP_DIR/$variant"
	dts_dir="$tree/target/linux/qualcommax/dts"
	led_dir="$tree/target/linux/qualcommax/ipq60xx/base-files/etc/board.d"

	mkdir -p "$dts_dir" "$led_dir"
	cat > "$tree/target/linux/qualcommax/Makefile" <<'EOF'
KERNEL_PATCHVER:=6.12
EOF
	cat > "$dts_dir/ipq6000-m2.dts" <<'EOF'
/dts-v1/;
#include "ipq6000-cmiot.dtsi"
/ { model = "ZN M2 test fixture"; };
EOF
	cat > "$led_dir/01_leds" <<'EOF'
#!/bin/sh
case "$board_name" in
zn,m2)
	ucidef_set_led_netdev "wan" "WAN" "blue:wan" "wan"
	ucidef_set_led_netdev "lan" "LAN" "blue:lan" "br-lan"
	;;
esac
EOF
}

run_hardware_patch() {
	variant="$1"
	tree="$TMP_DIR/$variant"
	(
		cd "$tree"
		awk '
			/^remove_blank_root_ssh_patch$/ { next }
			/^guard_qualcommax_network_defaults$/ { next }
			/^patch_zn_m2_wired_only_hardware$/ { print; exit }
			{ print }
		' "$ROOT_DIR/libwrt.sh" | VARIANT_FILES="$variant" bash >/dev/null
	)
}

make_fixture files-256m
run_hardware_patch files-256m
run_hardware_patch files-256m

DTS_256M="$TMP_DIR/files-256m/target/linux/qualcommax/dts/ipq6000-m2.dts"
grep -Fq '/* WIFI_DISABLED_BY_BUILDER */' "$DTS_256M"
grep -Fq '/* WCSS_DISABLED_BY_BUILDER */' "$DTS_256M"
grep -Fq '&q6v5_wcss {' "$DTS_256M"
grep -Fq '/delete-property/ memory-region;' "$DTS_256M"
grep -Fq '/delete-node/ &q6_region;' "$DTS_256M"
if [ "$(grep -Fc 'WCSS_DISABLED_BY_BUILDER' "$DTS_256M")" -ne 1 ]; then
	echo "FAIL: 256M WCSS patch is not idempotent" >&2
	exit 1
fi

make_fixture files-1g
run_hardware_patch files-1g

DTS_1G="$TMP_DIR/files-1g/target/linux/qualcommax/dts/ipq6000-m2.dts"
grep -Fq '/* WIFI_DISABLED_BY_BUILDER */' "$DTS_1G"
if grep -Eq 'WCSS_DISABLED_BY_BUILDER|delete-node.*q6_region' "$DTS_1G"; then
	echo "FAIL: 256M WCSS memory patch leaked into the 1G variant" >&2
	exit 1
fi

echo "wired-only hardware regression tests passed"
