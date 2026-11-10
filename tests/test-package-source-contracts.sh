#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
LIBWRT="$ROOT_DIR/libwrt-6.12.sh"
PINNED="$ROOT_DIR/deps/libwrt-6.12.env"
WF_256="$ROOT_DIR/.github/workflows/zn-m2-256m-main-router.yml"
ATTRIBUTES="$ROOT_DIR/.gitattributes"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

for config in \
	"$ROOT_DIR/configs/zn-m2-libwrt-6.12-nss.config"; do
	grep -Fxq 'CONFIG_PACKAGE_luci-app-wol=y' "$config" ||
		fail "stock WOL is not selected in $(basename "$config")"
	grep -Fxq 'CONFIG_PACKAGE_luci-i18n-wol-zh-cn=y' "$config" ||
		fail "stock WOL translation is not selected in $(basename "$config")"
	if grep -Fq 'wolultra' "$config"; then
		fail "WOL Ultra remains selected in $(basename "$config")"
	fi
done

if grep -Eq '^WOLULTRA_' "$PINNED"; then
	fail 'obsolete WOL Ultra pins remain'
fi
if grep -Eq '^HOMEPROXY_(COMMIT|MAKEFILE_SHA256)=' "$PINNED"; then
	fail 'obsolete standalone HomeProxy pins remain'
fi
if grep -Eq '^SING_BOX_' "$PINNED"; then
	fail 'obsolete standalone sing-box pins remain'
fi
grep -Eq '^VIKINGYFY_COMMIT=[0-9a-f]{40}$' "$PINNED" ||
	fail 'VIKINGYFY feed pin is missing from pinned dependencies'

if grep -Fq 'wolultra' "$LIBWRT"; then
	fail 'WOL Ultra logic remains in libwrt-6.12.sh'
fi

if grep -Fq 'git clone https://github.com/immortalwrt/homeproxy' "$LIBWRT"; then
	fail 'standalone HomeProxy clone remains'
fi
if grep -Fq 'git clone https://github.com/VIKINGYFY/packages' "$LIBWRT"; then
	fail 'standalone VIKINGYFY clone remains'
fi
if grep -Eq 'HOMEPROXY_(COMMIT|MAKEFILE_SHA256)' "$LIBWRT"; then
	fail 'standalone HomeProxy pin logic remains in libwrt-6.12.sh'
fi
if grep -Eq 'SING_BOX_(VERSION|HASH)' "$LIBWRT"; then
	fail 'obsolete sing-box pin logic remains in libwrt-6.12.sh'
fi
if grep -Fq 'codeload.github.com/SagerNet/sing-box' "$LIBWRT"; then
	fail 'self-built sing-box source download remains in libwrt-6.12.sh'
fi
grep -Fq 'feeds/vikingfy/luci-app-homeproxy' "$LIBWRT" ||
	fail 'pinned VIKINGYFY HomeProxy path is not used'
grep -Fq 'feeds/vikingfy/sing-box' "$LIBWRT" ||
	fail 'pinned VIKINGYFY sing-box path is not used'
grep -Fq 'package/feeds/luci/luci-app-homeproxy' "$LIBWRT" ||
	fail 'duplicate LuCI HomeProxy package is not removed'
grep -Fq 'package/feeds/packages/sing-box' "$LIBWRT" ||
	fail 'duplicate packages feed sing-box package is not removed'
grep -Fq 'ln -sfn' "$LIBWRT" ||
	fail 'VIKINGYFY feed symlink safety net is missing'
grep -Fq 'INCLUDE_HONK' "$LIBWRT" ||
	fail 'libwrt-6.12.sh has no honk branch'
grep -Fq 'zn-m2-honk-package.sh' "$LIBWRT" ||
	fail 'libwrt-6.12.sh does not stage the vendored honk package'
if grep -Fq 'packages-feed-compat.sh' "$LIBWRT" ||
   grep -Fq 'packages_feed_repair' "$LIBWRT" ||
   grep -Fq 'packages_feed_patch_is_known_legacy_safe' "$LIBWRT" ||
   grep -Fq 'FreeRADIUS OpenSSL dependency guard is missing after patch' "$LIBWRT" ||
   grep -Fq 'trafficshaper firewall variants are missing after patch' "$LIBWRT"; then
	fail 'obsolete packages feed compatibility hook remains in libwrt-6.12.sh'
fi
if [ -e "$ROOT_DIR/scripts/packages-feed-compat.sh" ] ||
   [ -e "$ROOT_DIR/tests/test-packages-feed-patches.sh" ] ||
   [ -d "$ROOT_DIR/patches/packages" ]; then
	fail 'obsolete packages feed compatibility files still exist'
fi
grep -Fxq 'deps/*.env text eol=lf' "$ATTRIBUTES" ||
	fail 'pinned dependency files are not normalized to LF'

for workflow in "$WF_256"; do
	grep -Fq "grep -q '^CONFIG_PACKAGE_luci-app-wol=y$' .config" "$workflow" ||
		fail "stock WOL config is not asserted by $(basename "$workflow")"
	grep -Fq "assert_config_absent 'CONFIG_PACKAGE_luci-app-wolultra=y'" "$workflow" ||
		fail "WOL Ultra exclusion is not asserted by $(basename "$workflow")"
	grep -Fq "assert_config_absent 'CONFIG_PACKAGE_luci-i18n-wolultra-zh-cn=y'" "$workflow" ||
		fail "WOL Ultra translation exclusion is not asserted by $(basename "$workflow")"
	grep -Fq 'luci-app-wol luci-i18n-wol-zh-cn etherwake' "$workflow" ||
		fail "stock WOL final manifest is not asserted by $(basename "$workflow")"
	grep -Fq 'tests/test-package-source-contracts.sh' "$workflow" ||
		fail "package source tests are not run by $(basename "$workflow")"
done

grep -Fq "grep -q '^CONFIG_PACKAGE_honk=y$' .config" "$WF_256" ||
	fail '256M workflow does not require honk'
grep -Fq 'honk v2ray-geoip v2ray-geosite' "$WF_256" ||
	fail '256M final manifest does not require the honk stack'
grep -Fq 'luci-app-gecoosac gecoosac' "$WF_256" ||
	fail '256M final manifest does not require gecoosac'
if grep -Fq '$0 !~ /^VIKINGYFY_/' "$WF_256"; then
	fail '256M provenance manifest still hides the VIKINGYFY pin'
fi

for deps_file in deps/libwrt-6.12.env deps/immortalwrt-6.18.env; do
	grep -q '^VIKINGYFY_COMMIT=[0-9a-f]\{40\}$' "$ROOT_DIR/$deps_file" ||
		fail "$deps_file does not pin the VIKINGYFY package feed"
	done
if grep -Fq 'SING_BOX_REPO_URL' "$ROOT_DIR"/deps/*.env; then
	fail 'deps still track the standalone sing-box repository'
fi

echo "package source contract tests passed"
