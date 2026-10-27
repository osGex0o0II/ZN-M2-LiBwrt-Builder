#!/bin/sh

if [ "${ZN_M2_CONFIG_RESTORED:-0}" != "1" ] &&
   [ ! -f /sysupgrade.tgz ] && [ ! -f /tmp/sysupgrade.tar ]; then
	exit 0
fi

BOARD_NAME="${ZN_M2_BOARD_NAME:-$(cat /tmp/sysinfo/board_name 2>/dev/null || echo unknown)}"
[ "$BOARD_NAME" = "zn,m2" ] || exit 0

SHADOW_FILE="${ZN_M2_SHADOW_FILE:-/etc/shadow}"
LEGACY_ROOT_HASH="\$6\$znm2default\$nwo/WFy57vlrCL6TiFnP2Oi8qXUY70Q7ZK6H3FXrvE.gNPHToM/8vtpUZSEDNUdHiJl/z3kQqVBLkAzIIFglM0"
rc=0

if [ -f "$SHADOW_FILE" ]; then
	current_hash="$(sed -n 's/^root:\([^:]*\):.*$/\1/p' "$SHADOW_FILE")"
	if [ "$current_hash" = "$LEGACY_ROOT_HASH" ]; then
		shadow_tmp="${SHADOW_FILE}.tmp.$$"
		if cp -p "$SHADOW_FILE" "$shadow_tmp" &&
		   sed 's|^root:[^:]*:|root::|' "$SHADOW_FILE" > "$shadow_tmp" &&
		   mv -f "$shadow_tmp" "$SHADOW_FILE"; then
			logger -t zn-m2-upgrade "cleared legacy public root password; set a new password in LuCI" 2>/dev/null || true
		else
			rm -f "$shadow_tmp"
			rc=1
			logger -t zn-m2-upgrade "failed to clear legacy root password; will retry" 2>/dev/null || true
		fi
	fi
fi

firewall_state="$(uci -q show firewall 2>/dev/null || true)"

# Find the UCI section that owns a named rule. Anonymous sections use the
# generated cfgXXXXX names, so name matching is the stable lookup.
find_rule_section() {
	printf '%s\n' "$firewall_state" |
		sed -n "s/^firewall\.\([^.=]*\)\.name='$1'$/\1/p" |
		head -n 1
}

# Create a deterministic section when the named rule is missing.
prepare_rule_section() {
	name="$1"
	fallback="$2"
	section="$(find_rule_section "$name")"
	if [ -z "$section" ]; then
		section="$fallback"
		uci -q set "firewall.$section=rule" || rc=1
	fi
	printf '%s\n' "$section"
}

# Repair each rule independently. Base fields are overwritten on purpose: these
# are system-managed rules, and the previous all-or-nothing check let a single
# existing rule suppress the other two.
mld_section="$(prepare_rule_section 'Allow-MLD' 'zn_m2_allow_mld')"
uci -q set "firewall.$mld_section.name=Allow-MLD" || rc=1
uci -q set "firewall.$mld_section.src=wan" || rc=1
uci -q set "firewall.$mld_section.proto=icmp" || rc=1
uci -q set "firewall.$mld_section.src_ip=fe80::/10" || rc=1
uci -q set "firewall.$mld_section.family=ipv6" || rc=1
uci -q set "firewall.$mld_section.target=ACCEPT" || rc=1
uci -q delete "firewall.$mld_section.icmp_type" 2>/dev/null || true
for icmp_type in 130/0 131/0 132/0 143/0; do
	uci -q add_list "firewall.$mld_section.icmp_type=$icmp_type" || rc=1
done

input_section="$(prepare_rule_section 'Allow-ICMPv6-Input' 'zn_m2_allow_icmpv6_input')"
uci -q set "firewall.$input_section.name=Allow-ICMPv6-Input" || rc=1
uci -q set "firewall.$input_section.src=wan" || rc=1
uci -q set "firewall.$input_section.proto=icmp" || rc=1
uci -q set "firewall.$input_section.limit=1000/sec" || rc=1
uci -q set "firewall.$input_section.family=ipv6" || rc=1
uci -q set "firewall.$input_section.target=ACCEPT" || rc=1
uci -q delete "firewall.$input_section.icmp_type" 2>/dev/null || true
for icmp_type in \
	echo-request echo-reply destination-unreachable packet-too-big \
	time-exceeded bad-header unknown-header-type router-solicitation \
	neighbour-solicitation router-advertisement neighbour-advertisement; do
	uci -q add_list "firewall.$input_section.icmp_type=$icmp_type" || rc=1
done

forward_section="$(prepare_rule_section 'Allow-ICMPv6-Forward' 'zn_m2_allow_icmpv6_forward')"
uci -q set "firewall.$forward_section.name=Allow-ICMPv6-Forward" || rc=1
uci -q set "firewall.$forward_section.src=wan" || rc=1
uci -q set "firewall.$forward_section.dest=*" || rc=1
uci -q set "firewall.$forward_section.proto=icmp" || rc=1
uci -q set "firewall.$forward_section.limit=1000/sec" || rc=1
uci -q set "firewall.$forward_section.family=ipv6" || rc=1
uci -q set "firewall.$forward_section.target=ACCEPT" || rc=1
uci -q delete "firewall.$forward_section.icmp_type" 2>/dev/null || true
for icmp_type in \
	echo-request echo-reply destination-unreachable packet-too-big \
	time-exceeded bad-header unknown-header-type; do
	uci -q add_list "firewall.$forward_section.icmp_type=$icmp_type" || rc=1
done

uci -q commit firewall || rc=1
logger -t zn-m2-upgrade "repaired IPv6 ICMP firewall policy" 2>/dev/null || true

exit "$rc"
