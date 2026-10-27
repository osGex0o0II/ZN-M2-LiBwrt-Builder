#!/bin/sh

# Preserved-config migrations for runtime defaults that must survive upgrades.
# Keep this separate from the fresh-install defaults: only touch infrastructure
# settings whose old value can break DHCP, NSS offload, or service health.

if [ "${ZN_M2_CONFIG_RESTORED:-0}" != "1" ] &&
   [ ! -f /sysupgrade.tgz ] && [ ! -f /tmp/sysupgrade.tar ]; then
	exit 0
fi

CONFIG_DIR="${ZN_M2_CONFIG_DIR:-/etc/config}"
INIT_DIR="${ZN_M2_INIT_DIR:-/etc/init.d}"
CRON_FILE="${ZN_M2_CRON_FILE:-/etc/crontabs/root}"
CRON_LINE="*/10 * * * * MIN_MEM_KB=40960 COOLDOWN_SEC=900 /usr/sbin/zn-m2-healthcheck >/dev/null 2>&1"
rc=0

# Keep exactly one healthcheck cron entry, even when an older threshold line is
# present or the crontab has no trailing newline. The healthcheck is shipped in
# the image and is the only periodic DHCP/DNS/memory recovery path.
mkdir -p "$(dirname "$CRON_FILE")" || exit 1
touch "$CRON_FILE" || exit 1
tmp="${CRON_FILE}.tmp.$$"
if awk -v line="$CRON_LINE" '
	/zn-m2-healthcheck/ {
		if (!done) {
			print line
			done = 1
		}
		next
	}
	{ print }
	END {
		if (!done)
			print line
	}
' "$CRON_FILE" > "$tmp"; then
	mv -f "$tmp" "$CRON_FILE" || {
		rm -f "$tmp"
		rc=1
	}
	chmod 600 "$CRON_FILE" 2>/dev/null || rc=1
else
	rm -f "$tmp"
	rc=1
fi
if [ -x "${INIT_DIR}/cron" ]; then
	"${INIT_DIR}/cron" enable >/dev/null 2>&1 || rc=1
	"${INIT_DIR}/cron" restart >/dev/null 2>&1 || rc=1
fi

# NSS/ECM owns forwarding acceleration on the 6.12 build. A preserved
# flow-offloading setting conflicts with it, so clear both switches when the
# ECM config is present. Do not restart firewall from S10; commit only.
if [ -f "${CONFIG_DIR}/ecm" ]; then
	uci -q set firewall.@defaults[0].flow_offloading='0' || rc=1
	uci -q set firewall.@defaults[0].flow_offloading_hw='0' || rc=1
	uci -q commit firewall || rc=1
fi

# Disabled features should not leave enabled init hooks behind. This removes
# the boot-time zerotier/miniupnpd failures without changing the feature policy.
if [ "$(uci -q get zerotier.global.enabled 2>/dev/null || echo 1)" = "0" ] &&
   [ -x "${INIT_DIR}/zerotier" ]; then
	"${INIT_DIR}/zerotier" disable >/dev/null 2>&1 || true
	"${INIT_DIR}/zerotier" stop >/dev/null 2>&1 || true
fi
if [ "$(uci -q get upnpd.config.enabled 2>/dev/null || echo 1)" = "0" ] &&
   [ -x "${INIT_DIR}/miniupnpd" ]; then
	"${INIT_DIR}/miniupnpd" disable >/dev/null 2>&1 || true
	"${INIT_DIR}/miniupnpd" stop >/dev/null 2>&1 || true
fi

# Preserve an explicit administrator choice unless it is unset or still the
# upstream default. lzo-rle gives better compression on this small device.
zram_algo="$(uci -q get system.@system[0].zram_comp_algo 2>/dev/null || true)"
case "$zram_algo" in
	''|lzo)
		uci -q set system.@system[0].zram_comp_algo='lzo-rle' || rc=1
		uci -q commit system || rc=1
		;;
esac

exit "$rc"
