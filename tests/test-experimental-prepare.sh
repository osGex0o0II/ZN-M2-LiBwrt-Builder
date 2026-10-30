#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
source "$root/scripts/experimental-build.sh"
mkdir -p "$tmp/native" "$tmp/aurora"
printf 'src-git packages https://example.org/packages.git^aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\nsrc-git fanchmwrt https://example.org/fwx.git\n' > "$tmp/native/feeds.conf.default"
FEED_FANCHMWRT_COMMIT=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
SOFTWARE_POLICY=upstream-native
pin_native_feeds "$tmp/native"
grep -Fxq 'src-git fanchmwrt https://example.org/fwx.git^bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' "$tmp/native/feeds.conf"
if grep -q vikingfy "$tmp/native/feeds.conf"; then echo 'FAIL: native feed replaced' >&2; exit 1; fi
mkdir -p "$tmp/native/files/etc/config"
printf 'native FWX identity\n' > "$tmp/native/files/etc/config/luci"
PROFILE_ID=fanchmwrt-25.12 ACCELERATION_POLICY=upstream-native
stage_profile_files "$tmp/native"
grep -Fxq 'native FWX identity' "$tmp/native/files/etc/config/luci"
test -f "$tmp/native/files/usr/sbin/zn-m2-diagnostics"
test ! -e "$tmp/native/files/usr/sbin/zn-m2-healthcheck"
report=$(ZN_M2_DIAGNOSTICS_ROOT="$tmp/native/files" sh "$tmp/native/files/usr/sbin/zn-m2-diagnostics")
[[ "$report" == *'profile=fanchmwrt-25.12'* ]]
[[ "$report" == *'does not prove active acceleration'* ]]
test ! -e "$tmp/native/files/etc/uci-defaults/99-set-ui.sh"
test ! -e "$tmp/native/files/etc/uci-defaults/zz-mainrouter-stability.sh"
printf 'src-git packages https://example.org/packages.git\n' > "$tmp/aurora/feeds.conf.default"
SOFTWARE_POLICY=aurora-homeproxy
FEED_PACKAGES_COMMIT=cccccccccccccccccccccccccccccccccccccccc
VIKINGYFY_COMMIT=dddddddddddddddddddddddddddddddddddddddd
pin_native_feeds "$tmp/aurora"
grep -Fxq 'src-git vikingfy https://github.com/VIKINGYFY/packages.git^dddddddddddddddddddddddddddddddddddddddd' "$tmp/aurora/feeds.conf"
ACCELERATION_POLICY=nss PROFILE_ID=immortalwrt-viking-main-nss
stage_profile_files "$tmp/aurora"
grep -Fxq nss "$tmp/aurora/files/etc/zn-m2-acceleration-policy"
test -e "$tmp/aurora/files/etc/uci-defaults/99-set-ui.sh"
unset FEED_PACKAGES_COMMIT
if pin_native_feeds "$tmp/aurora"; then echo 'FAIL: floating feed accepted' >&2; exit 1; fi
echo 'experimental preparation tests passed'
