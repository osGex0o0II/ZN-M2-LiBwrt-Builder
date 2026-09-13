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

if grep -Fq 'wolultra' "$LIBWRT"; then
	fail 'WOL Ultra logic remains in libwrt.sh'
fi

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
grep -Fq "\$0 !~ /^SING_BOX_/" "$WF_256" ||
	fail '256M provenance manifest does not exclude only the unused sing-box pins'

if grep -Fq 'wolultra' "$AUTO_UPDATE"; then
	fail 'dependency updater still manages WOL Ultra'
fi
grep -Fq 'SING_BOX_REPO_URL: https://github.com/SagerNet/sing-box.git' "$AUTO_UPDATE" ||
	fail 'dependency updater does not define the sing-box Git source'
grep -Fq "grep -E '^v[0-9]+\\.[0-9]+\\.[0-9]+$'" "$AUTO_UPDATE" ||
	fail 'dependency updater does not restrict sing-box to stable semver tags'
if grep -Fq 'api.github.com/repos/SagerNet/sing-box/releases/latest' "$AUTO_UPDATE"; then
	fail 'dependency updater still depends on the rate-limited GitHub releases API'
fi
if grep -Fq 'HOMEPROXY_REPO_URL:' "$AUTO_UPDATE"; then
	fail 'dependency updater still follows standalone HomeProxy'
fi
if grep -Eq 'homeproxy_(commit|makefile_sha256)' "$AUTO_UPDATE"; then
	fail 'dependency updater still emits standalone HomeProxy outputs'
fi

echo "package source contract tests passed"
