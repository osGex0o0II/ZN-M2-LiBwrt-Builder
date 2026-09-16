#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
LIBWRT="$ROOT_DIR/libwrt.sh"
PINNED="$ROOT_DIR/deps/pinned-deps.env"
AUTO_UPDATE="$ROOT_DIR/.github/workflows/auto-update-pinned-deps.yml"
WF_1G="$ROOT_DIR/.github/workflows/zn-m2-1g-proxy-gateway.yml"
WF_256="$ROOT_DIR/.github/workflows/zn-m2-256m-main-router.yml"
ATTRIBUTES="$ROOT_DIR/.gitattributes"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

for config in \
	"$ROOT_DIR/configs/zn-m2-1g-proxygateway.config" \
	"$ROOT_DIR/configs/zn-m2-256m-mainrouter.config"; do
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
	fail 'WOL Ultra logic remains in libwrt.sh'
fi

if grep -Fq 'git clone https://github.com/immortalwrt/homeproxy' "$LIBWRT"; then
	fail 'standalone HomeProxy clone remains'
fi
if grep -Fq 'git clone https://github.com/VIKINGYFY/packages' "$LIBWRT"; then
	fail 'standalone VIKINGYFY clone remains'
fi
if grep -Eq 'HOMEPROXY_(COMMIT|MAKEFILE_SHA256)' "$LIBWRT"; then
	fail 'standalone HomeProxy pin logic remains in libwrt.sh'
fi
if grep -Eq 'SING_BOX_(VERSION|HASH)' "$LIBWRT"; then
	fail 'obsolete sing-box pin logic remains in libwrt.sh'
fi
if grep -Fq 'codeload.github.com/SagerNet/sing-box' "$LIBWRT"; then
	fail 'self-built sing-box source download remains in libwrt.sh'
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
grep -Fq 'scripts/packages-feed-compat.sh' "$LIBWRT" ||
	fail 'shared packages feed compatibility library is not loaded by libwrt.sh'
grep -Fq 'packages_feed_repair "$packages_feed_dir" "$builder_root/patches/packages"' "$LIBWRT" ||
	fail 'shared packages feed repair entrypoint is not called by libwrt.sh'
if grep -Fq 'packages_feed_patch_is_known_legacy_safe' "$LIBWRT" ||
   grep -Fq 'FreeRADIUS OpenSSL dependency guard is missing after patch' "$LIBWRT" ||
   grep -Fq 'trafficshaper firewall variants are missing after patch' "$LIBWRT"; then
	fail 'obsolete duplicated packages feed validation remains in libwrt.sh'
fi
grep -Fxq 'deps/*.env text eol=lf' "$ATTRIBUTES" ||
	fail 'pinned dependency files are not normalized to LF'

for workflow in "$WF_1G" "$WF_256"; do
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

grep -Fq 'luci-app-homeproxy sing-box luci-i18n-homeproxy-zh-cn' "$WF_1G" ||
	fail '1G final manifest does not require HomeProxy, translation, and sing-box'
grep -Fq "assert_config_absent 'CONFIG_PACKAGE_luci-i18n-homeproxy-zh-cn=y'" "$WF_256" ||
	fail '256M config does not exclude the HomeProxy translation'
grep -Fq 'luci-app-homeproxy|luci-i18n-homeproxy-[^ ]+|sing-box' "$WF_256" ||
	fail '256M final manifest does not exclude proxy packages'
grep -Fq "\$0 !~ /^VIKINGYFY_/" "$WF_256" ||
	fail '256M provenance manifest does not exclude only the unused VIKINGYFY pins'

if grep -Fq 'wolultra' "$AUTO_UPDATE"; then
	fail 'dependency updater still manages WOL Ultra'
fi
if grep -Fq 'SING_BOX_REPO_URL' "$AUTO_UPDATE"; then
	fail 'dependency updater still tracks the standalone sing-box repository'
fi
if grep -Fq 'codeload.github.com/SagerNet/sing-box' "$AUTO_UPDATE"; then
	fail 'dependency updater still downloads the sing-box tarball'
fi
grep -Fq 'VIKINGYFY_REPO_URL: https://github.com/VIKINGYFY/packages.git' "$AUTO_UPDATE" ||
	fail 'dependency updater does not track the VIKINGYFY package feed'
if grep -Fq 'HOMEPROXY_REPO_URL:' "$AUTO_UPDATE"; then
	fail 'dependency updater still follows standalone HomeProxy'
fi
if grep -Eq 'homeproxy_(commit|makefile_sha256)' "$AUTO_UPDATE"; then
	fail 'dependency updater still emits standalone HomeProxy outputs'
fi

echo "package source contract tests passed"
