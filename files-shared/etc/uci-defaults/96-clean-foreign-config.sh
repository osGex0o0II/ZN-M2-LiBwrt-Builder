#!/bin/sh
# Cross-distro flashes keep /etc/config from images that shipped a different
# package set (LEDE: ssr-plus, 3proxy, vlmcsd, ...). Drop configuration for
# packages this image does not install, so uci and dnsmasq stop loading it on
# every boot. A package that is still installed keeps its configuration.

CONFIG_DIR="${ZN_M2_CONFIG_DIR:-/etc/config}"
INIT_DIR="${ZN_M2_INIT_DIR:-/etc/init.d}"
dnsmasq_d="${ZN_M2_DNSMASQ_D:-/etc/dnsmasq.d}"
rc=0

for stale in 3proxy shadowsocksr vlmcsd vsftpd microsocks nlbwmon oui arpbind appfilter; do
	[ -f "${CONFIG_DIR}/${stale}" ] || continue
	[ -x "${INIT_DIR}/${stale}" ] && continue
	rm -f "${CONFIG_DIR}/${stale}" || rc=1
	logger -t zn-m2 "removed stale config ${stale}" 2>/dev/null || true
done

# ssr-plus drops resolver fragments into dnsmasq's confdir. They keep pointing
# at a proxy that no longer exists, so remove them with the package.
if [ ! -x "${INIT_DIR}/shadowsocksr" ]; then
	rm -f "${dnsmasq_d}/dnsmasq-ssrplus.conf" || rc=1
	rm -rf "${dnsmasq_d}/dnsmasq-ssrplus.d" || rc=1
fi

exit "$rc"
