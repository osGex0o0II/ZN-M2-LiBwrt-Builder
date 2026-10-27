#!/bin/sh

# Service, DNS, and UI choices are factory defaults. Never reset them when
# sysupgrade has restored the administrator's configuration archive.
if [ "${ZN_M2_CONFIG_RESTORED:-0}" = "1" ] ||
   [ -f /sysupgrade.tgz ] || [ -f /tmp/sysupgrade.tar ]; then
	echo "Preserved configuration detected; skip 256M stability defaults"
	exit 0
fi

# 256M main router stability defaults. Keep the profile conservative: stable
# DNS entrypoint, no always-on web terminal, and low-frequency health checks.

# Use WAN-provided resolvers by default. Administrators can still opt into a
# fixed resolver policy through LuCI without it being overwritten on upgrade.
uci -q set dhcp.@dnsmasq[0].noresolv='0'
uci -q set dhcp.@dnsmasq[0].localservice='1'
uci -q set dhcp.@dnsmasq[0].ednspacket_max='1232'
uci -q set dhcp.@dnsmasq[0].dnsforwardmax='300'

# LuCI overview loads multiple status cards in parallel; keep a little more
# uhttpd request headroom so the first dashboard paint is less serialized.
uci -q set uhttpd.main.max_requests='8'

uci commit dhcp
uci commit uhttpd

[ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd restart 2>/dev/null || true

# UPnP and ZeroTier stay feature-disabled by default. Their service policy is
# owned by 99-set-ui.sh so fresh installs and upgrades cannot disagree.
uci -q set upnpd.config.enabled='0'
uci -q set zerotier.global.enabled='0'
uci -q set zerotier.earth.enabled='0'
uci -q commit upnpd
uci -q commit zerotier

# TTYD remains packaged for recovery, but stays off until manually enabled.
[ -x /etc/init.d/ttyd ] && /etc/init.d/ttyd disable 2>/dev/null || true
[ -x /etc/init.d/ttyd ] && /etc/init.d/ttyd stop 2>/dev/null || true

# HomeProxy is installed and its init is enabled, but it stays idle until a
# node/subscription is configured (main_node defaults to nil).
[ -x /etc/init.d/homeproxy ] && /etc/init.d/homeproxy enable 2>/dev/null || true

# gecoosac ships installed but stays stopped: it is the AC controller for
# 集客 APs and has no role on a plain main router.
[ -x /etc/init.d/gecoosac ] && /etc/init.d/gecoosac disable 2>/dev/null || true
[ -x /etc/init.d/gecoosac ] && /etc/init.d/gecoosac stop 2>/dev/null || true

# The 256M build checks less frequently to avoid background noise on a
# constrained device. With the proxy stack installed, keep a warning-only
# threshold with a little more lead time than the bare router.
# 40MiB (warning-only) gives one cron interval of extra lead time over 32MiB.
CRON_FILE="/etc/crontabs/root"
CRON_LINE="*/10 * * * * MIN_MEM_KB=40960 COOLDOWN_SEC=900 /usr/sbin/zn-m2-healthcheck >/dev/null 2>&1"
mkdir -p /etc/crontabs
touch "$CRON_FILE"
grep -Fxq "$CRON_LINE" "$CRON_FILE" 2>/dev/null || echo "$CRON_LINE" >> "$CRON_FILE"

[ -x /etc/init.d/cron ] && /etc/init.d/cron enable 2>/dev/null || true
[ -x /etc/init.d/cron ] && /etc/init.d/cron restart 2>/dev/null || true

exit 0
