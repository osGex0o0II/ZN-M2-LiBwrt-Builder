#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
SOURCE_ROOT="${1:-${OPENWRT_SOURCE_DIR:-}}"
PATCH_DIR="$ROOT_DIR/patches/packages"
COMPAT_LIB="$ROOT_DIR/scripts/packages-feed-compat.sh"
FREERADIUS_PATCH="$PATCH_DIR/freeradius3-kconfig-recursive-dependency.patch"
TRAFFICSHAPER_PATCH="$PATCH_DIR/trafficshaper-kconfig-recursive-dependency.patch"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

[ -f "$COMPAT_LIB" ] || fail 'missing shared packages feed compatibility library'
# shellcheck disable=SC1090
. "$COMPAT_LIB"

assert_eq() {
	expected="$1"
	actual="$2"
	message="$3"
	[ "$actual" = "$expected" ] || fail "$message: expected $expected, got $actual"
}

commit_fixture() {
	fixture_dir="$1"
	git -C "$fixture_dir" init -q
	git -C "$fixture_dir" add .
	git -C "$fixture_dir" \
		-c user.name='Packages Feed Test' \
		-c user.email='packages-feed-test@example.invalid' \
		commit -qm fixture
}

write_legacy_fixture() {
	fixture_dir="$1"
	mkdir -p \
		"$fixture_dir/net/freeradius3" \
		"$fixture_dir/net/trafficshaper"
	cat > "$fixture_dir/net/freeradius3/Makefile" <<'EOF'
PKG_NAME:=freeradius3
PKG_VERSION:=3.2.8
define Package/freeradius3
  DEPENDS:=+freeradius3-common
endef
define Package/freeradius3-common
  DEPENDS:= +FREERADIUS3_OPENSSL:libopenssl +libcap
endef
define Package/freeradius3-utils
  DEPENDS:=+freeradius3-common
endef
EOF
	cat > "$fixture_dir/net/trafficshaper/Makefile" <<'EOF'
PKG_NAME:=trafficshaper
PKG_RELEASE:=3
define Package/trafficshaper
  DEPENDS:=+tc +kmod-sched-core +iptables +IPV6:ip6tables +kmod-sched-cake +iptables-mod-conntrack-extra
endef
$(eval $(call BuildPackage,trafficshaper))
EOF
	commit_fixture "$fixture_dir"
}

write_modern_fixture() {
	fixture_dir="$1"
	mkdir -p \
		"$fixture_dir/net/freeradius3" \
		"$fixture_dir/net/trafficshaper"
	cat > "$fixture_dir/net/freeradius3/Makefile" <<'EOF'
PKG_NAME:=freeradius3
PKG_VERSION:=3.2.10
define Package/freeradius3
  DEPENDS:=+freeradius3-common +FREERADIUS3_OPENSSL:libopenssl +FREERADIUS3_OPENSSL:libopenssl-legacy
endef
define Package/freeradius3-common
  DEPENDS:= +FREERADIUS3_OPENSSL:libopenssl +FREERADIUS3_OPENSSL:libopenssl-legacy +libcap
endef
define Package/freeradius3-utils
  DEPENDS:=+freeradius3-common +FREERADIUS3_OPENSSL:libopenssl +FREERADIUS3_OPENSSL:libopenssl-legacy
endef
EOF
	cat > "$fixture_dir/net/trafficshaper/Makefile" <<'EOF'
PKG_NAME:=trafficshaper
PKG_RELEASE:=5
define Package/trafficshaper/Default
  PROVIDES:=trafficshaper
endef
define Package/trafficshaper
  $(call Package/trafficshaper/Default)
  DEPENDS+= +nftables
  VARIANT:=nftables
  DEFAULT_VARIANT:=1
endef
define Package/trafficshaper-iptables
  $(call Package/trafficshaper/Default)
  DEPENDS+= +iptables +IPV6:ip6tables +iptables-mod-conntrack-extra
  VARIANT:=iptables
  CONFLICTS:=trafficshaper
endef
$(eval $(call BuildPackage,trafficshaper))
$(eval $(call BuildPackage,trafficshaper-iptables))
EOF
	commit_fixture "$fixture_dir"
}

write_forward_fixture() {
	fixture_dir="$1"
	mkdir -p \
		"$fixture_dir/net/freeradius3" \
		"$fixture_dir/net/trafficshaper"
	cat > "$fixture_dir/net/freeradius3/Makefile" <<'EOF'
# fixture padding 1
# fixture padding 2
# fixture padding 3
# fixture padding 4
# fixture padding 5
# fixture padding 6
# fixture padding 7
include $(TOPDIR)/rules.mk

PKG_NAME:=freeradius3
PKG_VERSION:=3.2.10
PKG_VERSION_UNDERSCORE:=$(subst .,_,${PKG_VERSION})
PKG_RELEASE:=1

PKG_SOURCE:=freeradius-server-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/FreeRADIUS/freeradius-server/releases/download/release_$(PKG_VERSION_UNDERSCORE)/

define Package/freeradius3-common
  DEPENDS:= +FREERADIUS3_OPENSSL:libopenssl +FREERADIUS3_OPENSSL:libopenssl-legacy +libcap
endef
EOF
	while [ "$(wc -l < "$fixture_dir/net/freeradius3/Makefile")" -lt 45 ]; do
		printf '\n' >> "$fixture_dir/net/freeradius3/Makefile"
	done
	cat >> "$fixture_dir/net/freeradius3/Makefile" <<'EOF'

define Package/freeradius3
  $(call Package/freeradius3/Default)
  DEPENDS:=+freeradius3-common
  TITLE:=A flexible RADIUS server (version 3)
endef
EOF
	printf '\n' >> "$fixture_dir/net/freeradius3/Makefile"
	while [ "$(wc -l < "$fixture_dir/net/freeradius3/Makefile")" -lt 708 ]; do
		printf '\n' >> "$fixture_dir/net/freeradius3/Makefile"
	done
	printf 'endef\n\n' >> "$fixture_dir/net/freeradius3/Makefile"
	cat >> "$fixture_dir/net/freeradius3/Makefile" <<'EOF'
define Package/freeradius3-utils
  $(call Package/freeradius3/Default)
  DEPENDS:=+freeradius3-common
  TITLE:=Misc. client utilities
endef
EOF
	printf '\n' >> "$fixture_dir/net/freeradius3/Makefile"
	cat > "$fixture_dir/net/trafficshaper/Makefile" <<'EOF'
# fixture padding 1
# fixture padding 2
# fixture padding 3
# fixture padding 4
# fixture padding 5
# fixture padding 6
include $(TOPDIR)/rules.mk

PKG_NAME:=trafficshaper
PKG_VERSION:=1.0.0
PKG_RELEASE:=4
PKG_MAINTAINER:=Luiz Angelo Daros de Luca <luizluca@gmail.com>

PKG_LICENSE:=GPL-2.0-or-later

include $(INCLUDE_DIR)/package.mk

define Package/trafficshaper
  SECTION:=net
  CATEGORY:=Network
  TITLE:=WAN traffic shaper based on LAN addresses
  DEPENDS:=+tc +kmod-sched-core +kmod-sched-connmark +kmod-ifb \
	+(PACKAGE_nftables-json||PACKAGE_nftables-nojson):nftables \
	+!(PACKAGE_nftables-json||PACKAGE_nftables-nojson):iptables \
	+(IPV6&&!(PACKAGE_nftables-json||PACKAGE_nftables-nojson)):ip6tables \
	+kmod-sched-cake \
	+!(PACKAGE_nftables-json||PACKAGE_nftables-nojson):iptables-mod-conntrack-extra
  PKGARCH:=all
endef

define Package/trafficshaper/description
  Setup QoS rules to limit (or reserve) traffic used by classes of clients.
  Uplink and downlink can be controlled (or not controlled) independently.
  the use (or not) of spare wan bandwidth when available.
endef

define Package/trafficshaper/conffiles
/etc/config/trafficshaper
endef

define Build/Compile
endef

define Package/trafficshaper/install
	$(INSTALL_BIN) ./files/trafficshaper.init $(1)/etc/init.d/trafficshaper
endef

$(eval $(call BuildPackage,trafficshaper))
EOF
	commit_fixture "$fixture_dir"
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

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/packages-feed-compat.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

legacy_feed="$TMP_ROOT/legacy"
write_legacy_fixture "$legacy_feed"
assert_eq legacy-safe \
	"$(packages_feed_patch_state "$legacy_feed" "$FREERADIUS_PATCH")" \
	'FreeRADIUS legacy feed classification failed'
assert_eq legacy-safe \
	"$(packages_feed_patch_state "$legacy_feed" "$TRAFFICSHAPER_PATCH")" \
	'trafficshaper legacy feed classification failed'
packages_feed_repair "$legacy_feed" "$PATCH_DIR"
[ -z "$(git -C "$legacy_feed" status --short)" ] ||
	fail 'legacy-safe repair mutated the packages feed'

modern_feed="$TMP_ROOT/modern"
write_modern_fixture "$modern_feed"
assert_eq modern-fixed \
	"$(packages_feed_patch_state "$modern_feed" "$FREERADIUS_PATCH")" \
	'FreeRADIUS modern feed classification failed'
assert_eq modern-fixed \
	"$(packages_feed_patch_state "$modern_feed" "$TRAFFICSHAPER_PATCH")" \
	'trafficshaper modern feed classification failed'
packages_feed_repair "$modern_feed" "$PATCH_DIR"
[ -z "$(git -C "$modern_feed" status --short)" ] ||
	fail 'modern-fixed repair mutated the packages feed'

partial_feed="$TMP_ROOT/partial"
cp -a "$modern_feed" "$partial_feed"
sed -i '/DEPENDS+= +nftables/d' "$partial_feed/net/trafficshaper/Makefile"
assert_eq invalid \
	"$(packages_feed_patch_state "$partial_feed" "$TRAFFICSHAPER_PATCH")" \
	'partial trafficshaper feed classification failed'
if packages_feed_repair "$partial_feed" "$PATCH_DIR" >/dev/null 2>&1; then
	fail 'partial packages feed was accepted'
fi

partial_traffic_variant_feed="$TMP_ROOT/partial-traffic-variant"
cp -a "$modern_feed" "$partial_traffic_variant_feed"
sed -i '/CONFLICTS:=trafficshaper/d' \
	"$partial_traffic_variant_feed/net/trafficshaper/Makefile"
assert_eq invalid \
	"$(packages_feed_patch_state "$partial_traffic_variant_feed" "$TRAFFICSHAPER_PATCH")" \
	'partial trafficshaper variant was accepted'
if packages_feed_repair "$partial_traffic_variant_feed" "$PATCH_DIR" >/dev/null 2>&1; then
	fail 'partial trafficshaper variant was accepted'
fi

partial_freeradius_feed="$TMP_ROOT/partial-freeradius"
cp -a "$modern_feed" "$partial_freeradius_feed"
sed -i \
	'/^define Package\/freeradius3-utils$/,/^endef$/ s/ +FREERADIUS3_OPENSSL:libopenssl +FREERADIUS3_OPENSSL:libopenssl-legacy//' \
	"$partial_freeradius_feed/net/freeradius3/Makefile"
assert_eq invalid \
	"$(packages_feed_patch_state "$partial_freeradius_feed" "$FREERADIUS_PATCH")" \
	'partial FreeRADIUS feed classification failed'
if packages_feed_repair "$partial_freeradius_feed" "$PATCH_DIR" >/dev/null 2>&1; then
	fail 'partial FreeRADIUS feed was accepted'
fi

unknown_feed="$TMP_ROOT/unknown"
cp -a "$legacy_feed" "$unknown_feed"
sed -i 's/PKG_VERSION:=3.2.8/PKG_VERSION:=3.2.9/' \
	"$unknown_feed/net/freeradius3/Makefile"
assert_eq invalid \
	"$(packages_feed_patch_state "$unknown_feed" "$FREERADIUS_PATCH")" \
	'unknown FreeRADIUS feed classification failed'
if packages_feed_repair "$unknown_feed" "$PATCH_DIR" >/dev/null 2>&1; then
	fail 'unknown packages feed was accepted'
fi

unknown_traffic_feed="$TMP_ROOT/unknown-trafficshaper"
cp -a "$legacy_feed" "$unknown_traffic_feed"
sed -i 's/PKG_RELEASE:=3/PKG_RELEASE:=2/' \
	"$unknown_traffic_feed/net/trafficshaper/Makefile"
assert_eq invalid \
	"$(packages_feed_patch_state "$unknown_traffic_feed" "$TRAFFICSHAPER_PATCH")" \
	'unknown trafficshaper feed classification failed'
if packages_feed_repair "$unknown_traffic_feed" "$PATCH_DIR" >/dev/null 2>&1; then
	fail 'unknown trafficshaper feed was accepted'
fi

commented_legacy_feed="$TMP_ROOT/commented-legacy"
cp -a "$legacy_feed" "$commented_legacy_feed"
sed -i 's/^  DEPENDS:= +FREERADIUS3_OPENSSL:/  # DEPENDS:= +FREERADIUS3_OPENSSL:/' \
	"$commented_legacy_feed/net/freeradius3/Makefile"
assert_eq invalid \
	"$(packages_feed_patch_state "$commented_legacy_feed" "$FREERADIUS_PATCH")" \
	'commented FreeRADIUS legacy marker was accepted'

commented_modern_feed="$TMP_ROOT/commented-modern"
cp -a "$modern_feed" "$commented_modern_feed"
sed -i -e 's/^  DEPENDS:=/# DEPENDS:=/' \
	-e 's/^  DEPENDS+=/# DEPENDS+=/' \
	-e 's/^$(eval/# $(eval/' \
	-e 's/^  PROVIDES:=/# PROVIDES:=/' \
	"$commented_modern_feed/net/freeradius3/Makefile" \
	"$commented_modern_feed/net/trafficshaper/Makefile"
assert_eq invalid \
	"$(packages_feed_patch_state "$commented_modern_feed" "$FREERADIUS_PATCH")" \
	'commented FreeRADIUS modern marker was accepted'
assert_eq invalid \
	"$(packages_feed_patch_state "$commented_modern_feed" "$TRAFFICSHAPER_PATCH")" \
	'commented trafficshaper modern marker was accepted'

commented_traffic_legacy_feed="$TMP_ROOT/commented-traffic-legacy"
cp -a "$legacy_feed" "$commented_traffic_legacy_feed"
sed -i 's/^  DEPENDS:=+tc/# DEPENDS:=+tc/' \
	"$commented_traffic_legacy_feed/net/trafficshaper/Makefile"
assert_eq invalid \
	"$(packages_feed_patch_state "$commented_traffic_legacy_feed" "$TRAFFICSHAPER_PATCH")" \
	'commented trafficshaper legacy marker was accepted'

nested_parent="$TMP_ROOT/nested-parent"
mkdir -p "$nested_parent/feeds/packages/net/freeradius3" \
	"$nested_parent/feeds/packages/net/trafficshaper"
cp "$legacy_feed/net/freeradius3/Makefile" \
	"$nested_parent/feeds/packages/net/freeradius3/Makefile"
cp "$legacy_feed/net/trafficshaper/Makefile" \
	"$nested_parent/feeds/packages/net/trafficshaper/Makefile"
commit_fixture "$nested_parent"
if packages_feed_repair "$nested_parent/feeds/packages" "$PATCH_DIR" >/dev/null 2>&1; then
	fail 'packages feed nested under an enclosing repository was accepted'
fi

forward_feed="$TMP_ROOT/forward"
write_forward_fixture "$forward_feed"
assert_eq invalid \
	"$(packages_feed_patch_state "$forward_feed" "$FREERADIUS_PATCH")" \
	'forward FreeRADIUS fixture was not recognized as pre-patch'
assert_eq invalid \
	"$(packages_feed_patch_state "$forward_feed" "$TRAFFICSHAPER_PATCH")" \
	'forward trafficshaper fixture was not recognized as pre-patch'
packages_feed_repair "$forward_feed" "$PATCH_DIR"
assert_eq modern-fixed \
	"$(packages_feed_patch_state "$forward_feed" "$FREERADIUS_PATCH")" \
	'forward FreeRADIUS patch did not produce modern-fixed state'
assert_eq modern-fixed \
	"$(packages_feed_patch_state "$forward_feed" "$TRAFFICSHAPER_PATCH")" \
	'forward trafficshaper patch did not produce modern-fixed state'
packages_feed_repair "$forward_feed" "$PATCH_DIR"

if [ -n "$SOURCE_ROOT" ] &&
   [ "$(git -C "$SOURCE_ROOT/feeds/packages" rev-parse --is-inside-work-tree 2>/dev/null || true)" = true ]; then
	pinned_commit="$(sed -n 's/^FEED_PACKAGES_COMMIT=//p' "$ROOT_DIR/deps/pinned-deps.env")"
	actual_commit="$(git -C "$SOURCE_ROOT/feeds/packages" rev-parse HEAD)"
	assert_eq "$pinned_commit" "$actual_commit" \
		'OpenWrt source packages feed does not match the repository pin'

	pinned_feed="$TMP_ROOT/pinned"
	mkdir -p \
		"$pinned_feed/net/freeradius3" \
		"$pinned_feed/net/trafficshaper"
	cp "$SOURCE_ROOT/feeds/packages/net/freeradius3/Makefile" \
		"$pinned_feed/net/freeradius3/Makefile"
	cp "$SOURCE_ROOT/feeds/packages/net/trafficshaper/Makefile" \
		"$pinned_feed/net/trafficshaper/Makefile"
	commit_fixture "$pinned_feed"
	assert_eq legacy-safe \
		"$(packages_feed_patch_state "$pinned_feed" "$FREERADIUS_PATCH")" \
		'pinned FreeRADIUS feed classification failed'
	assert_eq legacy-safe \
		"$(packages_feed_patch_state "$pinned_feed" "$TRAFFICSHAPER_PATCH")" \
		'pinned trafficshaper feed classification failed'
	packages_feed_repair "$pinned_feed" "$PATCH_DIR"
	[ -z "$(git -C "$pinned_feed" status --short)" ] ||
		fail 'exact pinned packages feed was mutated'
else
	echo 'INFO: exact pinned OpenWrt source was not provided; local state fixtures passed'
fi

echo "packages feed compatibility state tests passed"
