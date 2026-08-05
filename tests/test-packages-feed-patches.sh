#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
SOURCE_ROOT="${1:-${OPENWRT_SOURCE_DIR:-}}"
PATCH_DIR="$ROOT_DIR/patches/packages"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

legacy_safe_patch_target() {
	case "$(basename "$1")" in
	freeradius3-kconfig-recursive-dependency.patch)
		grep -Fxq 'PKG_VERSION:=3.2.8' "$SOURCE_ROOT/feeds/packages/net/freeradius3/Makefile" &&
		grep -Fq 'DEPENDS:=+freeradius3-common' "$SOURCE_ROOT/feeds/packages/net/freeradius3/Makefile" &&
		! grep -Fq 'libopenssl-legacy' "$SOURCE_ROOT/feeds/packages/net/freeradius3/Makefile"
		;;
	trafficshaper-kconfig-recursive-dependency.patch)
		grep -Fxq 'PKG_RELEASE:=3' "$SOURCE_ROOT/feeds/packages/net/trafficshaper/Makefile" &&
		grep -Fq '+iptables +IPV6:ip6tables' "$SOURCE_ROOT/feeds/packages/net/trafficshaper/Makefile" &&
		! grep -Fq 'PACKAGE_nftables-' "$SOURCE_ROOT/feeds/packages/net/trafficshaper/Makefile" &&
		! grep -Fq 'Package/trafficshaper-iptables' "$SOURCE_ROOT/feeds/packages/net/trafficshaper/Makefile"
		;;
	*)
		return 1
		;;
	esac
}

for patch_file in \
	"$PATCH_DIR/freeradius3-kconfig-recursive-dependency.patch" \
	"$PATCH_DIR/trafficshaper-kconfig-recursive-dependency.patch"; do
	[ -f "$patch_file" ] || fail "missing packages feed patch: $patch_file"
done

grep -Fq '+FREERADIUS3_OPENSSL:libopenssl +FREERADIUS3_OPENSSL:libopenssl-legacy' \
	"$PATCH_DIR/freeradius3-kconfig-recursive-dependency.patch" ||
	fail 'FreeRADIUS patch does not carry the conditional OpenSSL dependencies'
grep -Fq 'Package/trafficshaper-iptables' \
	"$PATCH_DIR/trafficshaper-kconfig-recursive-dependency.patch" ||
	fail 'trafficshaper patch does not define the iptables variant'

if [ -z "$SOURCE_ROOT" ] || [ ! -d "$SOURCE_ROOT/feeds/packages/.git" ]; then
	echo "SKIP: static packages feed patch checks passed; OpenWrt source was not provided"
	exit 0
fi

for patch_file in \
	"$PATCH_DIR/freeradius3-kconfig-recursive-dependency.patch" \
	"$PATCH_DIR/trafficshaper-kconfig-recursive-dependency.patch"; do
	if git -C "$SOURCE_ROOT/feeds/packages" apply --check "$patch_file"; then
		continue
	fi
	legacy_safe_patch_target "$patch_file" ||
		fail "packages feed patch does not apply cleanly and feed is not a known safe legacy version: $(basename "$patch_file")"
done

echo "packages feed compatibility patch tests passed"
