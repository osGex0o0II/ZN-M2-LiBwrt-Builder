#!/bin/sh

if [ "${ZN_M2_CONFIG_RESTORED:-0}" != "1" ] &&
   [ ! -f /sysupgrade.tgz ] && [ ! -f /tmp/sysupgrade.tar ]; then
	exit 0
fi

BOARD_NAME="${ZN_M2_BOARD_NAME:-$(cat /tmp/sysinfo/board_name 2>/dev/null || echo unknown)}"
[ "$BOARD_NAME" = "zn,m2" ] || exit 0

SHADOW_FILE="${ZN_M2_SHADOW_FILE:-/etc/shadow}"
LEGACY_ROOT_HASH="\$6\$znm2default\$nwo/WFy57vlrCL6TiFnP2Oi8qXUY70Q7ZK6H3FXrvE.gNPHToM/8vtpUZSEDNUdHiJl/z3kQqVBLkAzIIFglM0"

if [ -f "$SHADOW_FILE" ]; then
	current_hash="$(sed -n 's/^root:\([^:]*\):.*$/\1/p' "$SHADOW_FILE")"
	if [ "$current_hash" = "$LEGACY_ROOT_HASH" ]; then
		shadow_tmp="${SHADOW_FILE}.tmp.$$"
		if cp -p "$SHADOW_FILE" "$shadow_tmp" &&
		   sed 's|^root:[^:]*:|root::|' "$SHADOW_FILE" > "$shadow_tmp"; then
			mv -f "$shadow_tmp" "$SHADOW_FILE"
		else
			rm -f "$shadow_tmp"
			exit 1
		fi
		logger -t zn-m2-upgrade "cleared legacy public root password; set a new password in LuCI" 2>/dev/null || true
	fi
fi

firewall_state="$(uci -q show firewall 2>/dev/null || true)"
has_rule() {
	printf '%s\n' "$firewall_state" | grep -Fq ".name='$1'"
}

if ! has_rule Allow-MLD &&
   ! has_rule Allow-ICMPv6-Input &&
   ! has_rule Allow-ICMPv6-Forward; then
	uci -q set firewall.zn_m2_allow_mld='rule'
	uci -q set firewall.zn_m2_allow_mld.name='Allow-MLD'
	uci -q set firewall.zn_m2_allow_mld.src='wan'
	uci -q set firewall.zn_m2_allow_mld.proto='icmp'
	uci -q set firewall.zn_m2_allow_mld.src_ip='fe80::/10'
	for icmp_type in 130/0 131/0 132/0 143/0; do
		uci -q add_list firewall.zn_m2_allow_mld.icmp_type="$icmp_type"
	done
	uci -q set firewall.zn_m2_allow_mld.family='ipv6'
	uci -q set firewall.zn_m2_allow_mld.target='ACCEPT'

	uci -q set firewall.zn_m2_allow_icmpv6_input='rule'
	uci -q set firewall.zn_m2_allow_icmpv6_input.name='Allow-ICMPv6-Input'
	uci -q set firewall.zn_m2_allow_icmpv6_input.src='wan'
	uci -q set firewall.zn_m2_allow_icmpv6_input.proto='icmp'
	for icmp_type in \
		echo-request echo-reply destination-unreachable packet-too-big \
		time-exceeded bad-header unknown-header-type router-solicitation \
		neighbour-solicitation router-advertisement neighbour-advertisement; do
		uci -q add_list firewall.zn_m2_allow_icmpv6_input.icmp_type="$icmp_type"
	done
	uci -q set firewall.zn_m2_allow_icmpv6_input.limit='1000/sec'
	uci -q set firewall.zn_m2_allow_icmpv6_input.family='ipv6'
	uci -q set firewall.zn_m2_allow_icmpv6_input.target='ACCEPT'

	uci -q set firewall.zn_m2_allow_icmpv6_forward='rule'
	uci -q set firewall.zn_m2_allow_icmpv6_forward.name='Allow-ICMPv6-Forward'
	uci -q set firewall.zn_m2_allow_icmpv6_forward.src='wan'
	uci -q set firewall.zn_m2_allow_icmpv6_forward.dest='*'
	uci -q set firewall.zn_m2_allow_icmpv6_forward.proto='icmp'
	for icmp_type in \
		echo-request echo-reply destination-unreachable packet-too-big \
		time-exceeded bad-header unknown-header-type; do
		uci -q add_list firewall.zn_m2_allow_icmpv6_forward.icmp_type="$icmp_type"
	done
	uci -q set firewall.zn_m2_allow_icmpv6_forward.limit='1000/sec'
	uci -q set firewall.zn_m2_allow_icmpv6_forward.family='ipv6'
	uci -q set firewall.zn_m2_allow_icmpv6_forward.target='ACCEPT'

	uci -q commit firewall
	logger -t zn-m2-upgrade "restored legacy-missing IPv6 ICMP policy" 2>/dev/null || true
fi

exit 0
