#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
source_tree=${1:-$root/.omo/sources/viking-main}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"; rm -f "$tmp.before" "$tmp.after"' EXIT
mkdir -p "$tmp/target/linux" "$tmp/package"
cp -R "$source_tree/target/linux/qualcommax" "$tmp/target/linux/"
cp -R "$source_tree/package/qca-nss" "$tmp/package/"
bash "$root/adapters/immortalwrt-viking-main-nss.sh" "$tmp"
dts=$tmp/target/linux/qualcommax/dts/ipq6000-m2.dts
grep -Fq '&nss_region { reg = <0x0 0x40000000 0x0 0x1000000>; };' "$dts"
grep -Fq '&wifi { status = "disabled"; };' "$dts"
grep -Fq '&usb3 { status = "disabled"; };' "$dts"
find "$tmp" -type f -exec sha256sum {} + | sort > "$tmp.before"
bash "$root/adapters/immortalwrt-viking-main-nss.sh" "$tmp"
find "$tmp" -type f -exec sha256sum {} + | sort > "$tmp.after"
cmp "$tmp.before" "$tmp.after"
rm "$tmp/target/linux/qualcommax/patches-6.18/0103-arm64-dts-ipq6018-add-reserved-memory-nodes.patch"
if bash "$root/adapters/immortalwrt-viking-main-nss.sh" "$tmp"; then exit 1; fi
rm -f "$tmp.before" "$tmp.after"
echo 'PASS: pinned-source adaptation, NSS retained, wireless/USB disabled, idempotent, missing layout rejected'
