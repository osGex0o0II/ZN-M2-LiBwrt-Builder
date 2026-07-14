#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
LIBWRT="$ROOT_DIR/libwrt.sh"
PINNED="$ROOT_DIR/deps/pinned-deps.env"
AUTO_UPDATE="$ROOT_DIR/.github/workflows/auto-update-pinned-deps.yml"
WF_1G="$ROOT_DIR/.github/workflows/zn-m2-1g-proxy-gateway.yml"
WF_256="$ROOT_DIR/.github/workflows/zn-m2-256m-main-router.yml"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

for config in \
	"$ROOT_DIR/configs/zn-m2-1g-proxygateway.config" \
	"$ROOT_DIR/configs/zn-m2-256m-mainrouter.config"; do
	grep -Fxq 'CONFIG_PACKAGE_luci-app-wolultra=y' "$config" ||
		fail "WOL Ultra is not selected in $(basename "$config")"
	grep -Fxq 'CONFIG_PACKAGE_luci-i18n-wolultra-zh-cn=y' "$config" ||
		fail "WOL Ultra translation is not selected in $(basename "$config")"
	if grep -Fxq 'CONFIG_PACKAGE_luci-app-wol=y' "$config" ||
		grep -Fxq 'CONFIG_PACKAGE_luci-i18n-wol-zh-cn=y' "$config"; then
		fail "stock WOL remains selected in $(basename "$config")"
	fi
done

grep -Eq '^WOLULTRA_COMMIT=[0-9a-f]{40}$' "$PINNED" ||
	fail 'WOL Ultra commit pin is missing'
grep -Eq '^WOLULTRA_TREE=[0-9a-f]{40}$' "$PINNED" ||
	fail 'WOL Ultra package tree pin is missing'
if grep -Eq '^HOMEPROXY_(COMMIT|MAKEFILE_SHA256)=' "$PINNED"; then
	fail 'obsolete standalone HomeProxy pins remain'
fi

grep -Fq 'https://github.com/VIKINGYFY/packages.git' "$LIBWRT" ||
	fail 'WOL Ultra source repository is not installed by libwrt.sh'
grep -Fq 'FETCH_HEAD:luci-app-wolultra' "$LIBWRT" ||
	fail 'WOL Ultra package subtree is not verified'

wol_line="$(grep -n 'Install pinned WOL Ultra' "$LIBWRT" | head -n1 | cut -d: -f1)"
skip_line="$(grep -n 'Skip HomeProxy for this build variant' "$LIBWRT" | head -n1 | cut -d: -f1)"
[ -n "$wol_line" ] && [ -n "$skip_line" ] && [ "$wol_line" -lt "$skip_line" ] ||
	fail 'WOL Ultra installation does not run for both variants'

if grep -Fq 'git clone https://github.com/immortalwrt/homeproxy' "$LIBWRT"; then
	fail 'standalone HomeProxy clone remains'
fi
if grep -Eq 'HOMEPROXY_(COMMIT|MAKEFILE_SHA256)' "$LIBWRT"; then
	fail 'standalone HomeProxy pin logic remains in libwrt.sh'
fi
grep -Fq 'feeds/luci/applications/luci-app-homeproxy' "$LIBWRT" ||
	fail 'pinned LuCI HomeProxy path is not used'
grep -Fq 'git -C feeds/luci apply --check' "$LIBWRT" ||
	fail 'HomeProxy patch preflight is missing'
grep -Fq -- '--directory=applications/luci-app-homeproxy' "$LIBWRT" ||
	fail 'HomeProxy patch is not mapped from the LuCI feed root'
grep -Fq 'get_direct_route_options' "$LIBWRT" ||
	fail 'positive HomeProxy direct-route guard is missing'

for workflow in "$WF_1G" "$WF_256"; do
	grep -Fq 'WOLULTRA_COMMIT WOLULTRA_TREE' "$workflow" ||
		fail "WOL Ultra pins are not required by $(basename "$workflow")"
	grep -Fq "grep -q '^CONFIG_PACKAGE_luci-app-wolultra=y$' .config" "$workflow" ||
		fail "WOL Ultra config is not asserted by $(basename "$workflow")"
	grep -Fq "assert_config_absent 'CONFIG_PACKAGE_luci-app-wol=y'" "$workflow" ||
		fail "stock WOL exclusion is not asserted by $(basename "$workflow")"
	grep -Fq "assert_config_absent 'CONFIG_PACKAGE_luci-i18n-wol-zh-cn=y'" "$workflow" ||
		fail "stock WOL translation exclusion is not asserted by $(basename "$workflow")"
	grep -Fq 'luci-app-wolultra luci-i18n-wolultra-zh-cn etherwake' "$workflow" ||
		fail "WOL Ultra final manifest is not asserted by $(basename "$workflow")"
	grep -Fq 'tests/test-package-source-contracts.sh' "$workflow" ||
		fail "package source tests are not run by $(basename "$workflow")"
	grep -Fq 'tests/test-wolultra-migration.sh' "$workflow" ||
		fail "WOL migration tests are not run by $(basename "$workflow")"
done

grep -Fq 'luci-app-homeproxy sing-box luci-i18n-homeproxy-zh-cn' "$WF_1G" ||
	fail '1G final manifest does not require HomeProxy, translation, and sing-box'
grep -Fq "assert_config_absent 'CONFIG_PACKAGE_luci-i18n-homeproxy-zh-cn=y'" "$WF_256" ||
	fail '256M config does not exclude the HomeProxy translation'
grep -Fq 'luci-app-homeproxy|luci-i18n-homeproxy-[^ ]+|sing-box|luci-app-wol' "$WF_256" ||
	fail '256M final manifest does not exclude proxy and stock WOL packages'
grep -Fq "\$0 !~ /^SING_BOX_/" "$WF_256" ||
	fail '256M provenance manifest does not exclude only the unused sing-box pins'

grep -Fq 'WOLULTRA_REPO_URL: https://github.com/VIKINGYFY/packages.git' "$AUTO_UPDATE" ||
	fail 'WOL Ultra is not managed by the dependency updater'
grep -Fq 'wolultra_tree=' "$AUTO_UPDATE" ||
	fail 'dependency updater does not resolve the WOL Ultra tree'
if grep -Fq 'HOMEPROXY_REPO_URL:' "$AUTO_UPDATE"; then
	fail 'dependency updater still follows standalone HomeProxy'
fi
if grep -Eq 'homeproxy_(commit|makefile_sha256)' "$AUTO_UPDATE"; then
	fail 'dependency updater still emits standalone HomeProxy outputs'
fi

echo "package source contract tests passed"
