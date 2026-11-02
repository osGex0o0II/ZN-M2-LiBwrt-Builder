#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
source "$root/scripts/validate-experimental-output.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf 'fwxd - 1\nkmod-fwx - 1\nluci-theme-fanchmwrt - 1\n' > "$tmp/native.manifest"
validate_experimental_manifest "$tmp/native.manifest" upstream-native upstream-native
printf 'kmod-qca-nss-drv - 1\nkmod-qca-nss-ecm - 1\nnss-firmware - 1\nluci-app-homeproxy - 1\nsing-box - 1\nluci-theme-aurora - 1\n' > "$tmp/nss.manifest"
validate_experimental_manifest "$tmp/nss.manifest" nss aurora-homeproxy
# LEDE ships the firmware per SoC and has no nss-firmware meta package.
printf 'kmod-qca-nss-drv - 1\nkmod-qca-nss-ecm - 1\nnss-firmware-ipq6018 - 1\nluci-app-homeproxy - 1\nsing-box - 1\nluci-theme-aurora - 1\n' > "$tmp/lede-nss.manifest"
validate_experimental_manifest "$tmp/lede-nss.manifest" nss aurora-homeproxy
printf 'kmod-qca-nss-drv - 1\nkmod-qca-nss-ecm - 1\nluci-app-homeproxy - 1\nsing-box - 1\nluci-theme-aurora - 1\n' > "$tmp/no-firmware.manifest"
if validate_experimental_manifest "$tmp/no-firmware.manifest" nss aurora-homeproxy; then echo 'FAIL: NSS firmware missing' >&2; exit 1; fi
printf 'kmod-ath11k-ahb - 1\n' >> "$tmp/nss.manifest"
if validate_experimental_manifest "$tmp/nss.manifest" nss aurora-homeproxy; then echo 'FAIL: wireless in final package closure' >&2; exit 1; fi
printf 'fwxd - 1\n' > "$tmp/incomplete.manifest"
if validate_experimental_manifest "$tmp/incomplete.manifest" upstream-native upstream-native; then echo 'FAIL: native UI/FWX missing' >&2; exit 1; fi
echo 'experimental manifest closure tests passed'
