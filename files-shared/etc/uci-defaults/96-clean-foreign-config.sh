#!/bin/sh
# Cross-distro flashes keep /etc/config from images that shipped a different
# package set (LEDE: ssr-plus, 3proxy, vlmcsd, ...). Drop configuration for
# packages this image does not install, so uci and dnsmasq stop loading it on
# every boot. A package that is still installed keeps its configuration, and
# some packages legitimately have no init script at all (oui, arpbind), so the
# guard checks ownership by package name, not just /etc/init.d.

CONFIG_DIR="${ZN_M2_CONFIG_DIR:-/etc/config}"
INIT_DIR="${ZN_M2_INIT_DIR:-/etc/init.d}"
dnsmasq_d="${ZN_M2_DNSMASQ_D:-/etc/dnsmasq.d}"
rc=0

pkg_installed() {
	if command -v apk >/dev/null 2>&1; then
		apk list --installed 2>/dev/null | grep -q "^$1-"
	else
		opkg list-installed 2>/dev/null | grep -q "^$1 "
	fi
}

# A package database that returns nothing is not proof that nothing is
# installed; deleting configs on that basis would be destructive.
pkg_db_ready() {
	if command -v apk >/dev/null 2>&1; then
		[ -n "$(apk list --installed 2>/dev/null | sed -n '1p')" ]
	else
		[ -n "$(opkg list-installed 2>/dev/null | sed -n '1p')" ]
	fi
}

if ! pkg_db_ready; then
	logger -t zn-m2 "package database unavailable; keeping existing configs" 2>/dev/null || true
	exit 0
fi

# config-name:owning-package[:alias...]
for entry in \
	3proxy:3proxy \
	shadowsocksr:shadowsocksr-libev \
	vlmcsd:vlmcsd \
	vsftpd:vsftpd \
	microsocks:microsocks \
	nlbwmon:nlbwmon \
	oui:luci-app-oui \
	arpbind:luci-app-arpbind \
	appfilter:luci-app-appfilter:luci-app-fwx-appfilter; do
	name="${entry%%:*}"
	pkgs="$(printf '%s' "${entry#*:}" | tr ':' ' ')"
	[ -f "${CONFIG_DIR}/${name}" ] || continue

	keep=0
	[ -x "${INIT_DIR}/${name}" ] && keep=1
	for pkg in $pkgs; do
		pkg_installed "$pkg" && keep=1
	done
	[ "$keep" = "1" ] && continue

	rm -f "${CONFIG_DIR}/${name}" || rc=1
	logger -t zn-m2 "removed stale config ${name}" 2>/dev/null || true
done

# ssr-plus drops resolver fragments into dnsmasq's confdir. They keep pointing
# at a proxy that no longer exists, so remove them with the package.
if [ ! -x "${INIT_DIR}/shadowsocksr" ] && ! pkg_installed shadowsocksr-libev; then
	rm -f "${dnsmasq_d}/dnsmasq-ssrplus.conf" || rc=1
	rm -rf "${dnsmasq_d}/dnsmasq-ssrplus.d" || rc=1
fi

exit "$rc"
