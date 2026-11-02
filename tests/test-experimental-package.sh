#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
source "$root/scripts/experimental-package.sh"
mkdir -p "$tmp/source/bin/targets/qualcommax/ipq60xx"
images="$tmp/source/bin/targets/qualcommax/ipq60xx"
printf 'factory fixture\n' > "$images/upstream-zn_m2-squashfs-factory.ubi"
printf 'upgrade fixture\n' > "$images/upstream-zn_m2-squashfs-sysupgrade.bin"
printf 'base-files - 1\n' > "$images/upstream.manifest"
printf 'CONFIG_TARGET_qualcommax=y\n' > "$tmp/source/.config"
printf 'source provenance\n' > "$tmp/source/BUILD-MANIFEST.txt"
factory_sha=$(sha256sum "$images/upstream-zn_m2-squashfs-factory.ubi" | cut -d' ' -f1)
upgrade_sha=$(sha256sum "$images/upstream-zn_m2-squashfs-sysupgrade.bin" | cut -d' ' -f1)
printf '{"profiles":{"zn_m2":{"images":[{"name":"upstream-zn_m2-squashfs-factory.ubi","sha256":"%s"},{"name":"upstream-zn_m2-squashfs-sysupgrade.bin","sha256":"%s"}]}}}\n' "$factory_sha" "$upgrade_sha" > "$images/profiles.json"
package_experimental "$tmp/source" "$tmp/release" immortalwrt-viking-main-nss 6.18.55 test
test -f "$tmp/release/ZN-M2-256M-immortalwrt-viking-main-nss-6.18.55-test-sysupgrade.bin"
(cd "$tmp/release"; sha256sum -c SHA256SUMS)
jq -e '.profiles.zn_m2.images | all(.name | startswith("ZN-M2-256M-immortalwrt-viking-main-nss-"))' "$tmp/release/profiles.json" >/dev/null
cp "$images/upstream-zn_m2-squashfs-factory.ubi" "$images/another-zn_m2-squashfs-factory.ubi"
if package_experimental "$tmp/source" "$tmp/duplicate" lede-master-nss 6.12.114 test; then
  echo 'FAIL: duplicate factory images accepted' >&2; exit 1
fi
rm "$images/another-zn_m2-squashfs-factory.ubi"
printf 'tampered\n' >> "$images/upstream-zn_m2-squashfs-sysupgrade.bin"
if package_experimental "$tmp/source" "$tmp/tampered" lede-master-nss 6.12.114 test; then
  echo 'FAIL: source image checksum mismatch accepted' >&2; exit 1
fi
echo 'experimental packaging tests passed'
