#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
SOURCE_ROOT="${1:-${OPENWRT_SOURCE_DIR:-}}"
PATCH_DIR="$ROOT_DIR/patches/packages"

fail() {
	echo "FAIL: $*" >&2
	exit 1
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
	git -C "$SOURCE_ROOT/feeds/packages" apply --check "$patch_file" ||
		fail "packages feed patch does not apply cleanly: $(basename "$patch_file")"
done

echo "packages feed compatibility patch tests passed"
