#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/init.d" "$TMP_DIR/evidence" \
	"$TMP_DIR/dnsmasq" "$TMP_DIR/proc"
SCRIPT="$TMP_DIR/zn-m2-healthcheck"
sed \
	-e "s#^PATH=.*#PATH='$TMP_DIR/bin:/usr/sbin:/usr/bin:/sbin:/bin'#" \
	-e "s#^STATE_DIR=.*#STATE_DIR='$TMP_DIR/state'#" \
	-e "s#/etc/init.d/#$TMP_DIR/init.d/#g" \
	"$ROOT_DIR/files/usr/sbin/zn-m2-healthcheck" > "$SCRIPT"
chmod +x "$SCRIPT"

cat > "$TMP_DIR/bin/ip" <<'EOF'
#!/bin/sh
[ "${HAS_DEFAULT_ROUTE:-1}" = "1" ] && echo "default via 192.0.2.1 dev eth0"
EOF
cat > "$TMP_DIR/bin/nslookup" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$TMP_DIR/bin/pidof" <<'EOF'
#!/bin/sh
exit 1
EOF
cat > "$TMP_DIR/bin/logger" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HEALTH_LOG"
EOF
cat > "$TMP_DIR/bin/uci" <<'EOF'
#!/bin/sh
case "$*" in
	*"dhcp.@dnsmasq[0].domain"*) echo lan ;;
	*"dhcp.lan.ignore"*) echo "${DHCP_IGNORE:-1}" ;;
	*"dhcp.lan.dhcpv4"*) echo "${DHCPV4:-server}" ;;
	*"system.@system[0].hostname"*) echo ZN-M2 ;;
	*"homeproxy.config.routing_mode"*) echo "${ROUTING_MODE:-bypass_mainland_china}" ;;
	*"homeproxy.config.main_node"*) echo "${MAIN_NODE:-nil}" ;;
	*"homeproxy.routing.default_outbound"*) echo "${DEFAULT_OUTBOUND:-nil}" ;;
	*"homeproxy.server.enabled"*) echo "${SERVER_ENABLED:-0}" ;;
esac
EOF
cat > "$TMP_DIR/init.d/homeproxy" <<'EOF'
#!/bin/sh
case "$1" in
	enabled) exit 0 ;;
	restart) echo restart >> "$SERVICE_LOG"; exit 0 ;;
esac
EOF
cat > "$TMP_DIR/init.d/dnsmasq" <<'EOF'
#!/bin/sh
if [ "$1" = "restart" ]; then
	echo "dnsmasq restart" >> "$SERVICE_LOG"
	if [ "${DNSMASQ_RECOVER:-0}" = "1" ]; then
		printf '%s\n' 'dhcp-range=set:lan,192.168.1.100,192.168.1.249,255.255.255.0,12h' \
			> "$DNSMASQ_CONFIG_FILE"
		printf '%s\n' \
			'  sl  local_address rem_address st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode' \
			'  1: 00000000:0043 00000000:0000 07 00000000:00000000 00:00000000 00000000     0        0 0 2 0000000000000000 0' \
			> "$PROC_NET_UDP"
	fi
	exit 0
fi
exit 1
EOF
chmod +x "$TMP_DIR/bin/"* "$TMP_DIR/init.d/homeproxy" \
	"$TMP_DIR/init.d/dnsmasq"

export HEALTH_LOG="$TMP_DIR/evidence/health.log"
export SERVICE_LOG="$TMP_DIR/evidence/service.log"
export DNSMASQ_CONFIG_FILE="$TMP_DIR/dnsmasq/dnsmasq.conf"
export PROC_NET_UDP="$TMP_DIR/proc/udp"
export PROC_NET_UDP6="$TMP_DIR/proc/udp6"
: > "$HEALTH_LOG"
: > "$SERVICE_LOG"
: > "$PROC_NET_UDP"
: > "$PROC_NET_UDP6"

MAIN_NODE=nil SERVER_ENABLED=0 ROUTING_MODE=bypass_mainland_china \
	STATE_OWNER="$(id -un):$(id -gn)" INIT_DIR="$TMP_DIR/init.d" \
	sh "$SCRIPT"
if [ -s "$SERVICE_LOG" ]; then
	echo "FAIL: unconfigured HomeProxy was restarted" >&2
	exit 1
fi

rm -rf "$TMP_DIR/state"
mkdir -p "$TMP_DIR/state"
echo 0 > "$TMP_DIR/evidence/victim"
ln -s "$TMP_DIR/evidence/victim" "$TMP_DIR/state/homeproxy.last"
MAIN_NODE=configured-node SERVER_ENABLED=0 ROUTING_MODE=bypass_mainland_china \
	STATE_OWNER="$(id -un):$(id -gn)" INIT_DIR="$TMP_DIR/init.d" \
	sh "$SCRIPT"
grep -Fxq restart "$SERVICE_LOG"
grep -Fxq 0 "$TMP_DIR/evidence/victim"
if [ -L "$TMP_DIR/state/homeproxy.last" ]; then
	echo "FAIL: cooldown state remains a symlink" >&2
	exit 1
fi
mode="$(stat -c '%a' "$TMP_DIR/state" 2>/dev/null || stat -f '%Lp' "$TMP_DIR/state")"
if [ "$mode" != 700 ]; then
	echo "FAIL: state directory mode is '$mode', expected 700" >&2
	exit 1
fi

reset_dhcp_case() {
	rm -rf "$TMP_DIR/state"
	mkdir -p "$TMP_DIR/state"
	rm -f "$TMP_DIR/dnsmasq/"*
	: > "$PROC_NET_UDP"
	: > "$PROC_NET_UDP6"
	: > "$HEALTH_LOG"
	: > "$SERVICE_LOG"
}

run_dhcp_case() {
	env \
		STATE_OWNER="$(id -un):$(id -gn)" \
		INIT_DIR="$TMP_DIR/init.d" \
		DNSMASQ_CONFIG_GLOB="$TMP_DIR/dnsmasq/*.conf" \
		PROC_NET_UDP="$PROC_NET_UDP" \
		PROC_NET_UDP6="$PROC_NET_UDP6" \
		DHCP_IGNORE="${DHCP_IGNORE:-0}" \
		DHCPV4="${DHCPV4:-server}" \
		HAS_DEFAULT_ROUTE="${HAS_DEFAULT_ROUTE:-0}" \
		DNSMASQ_RECOVER="${DNSMASQ_RECOVER:-0}" \
		sh "$SCRIPT" "${1:---dhcp-only}"
}

# LAN DHCP must be checked without a WAN/default route. A successful restart
# regenerates the range and opens UDP/67, which the same run must verify.
reset_dhcp_case
DHCP_IGNORE=0 HAS_DEFAULT_ROUTE=0 DNSMASQ_RECOVER=1 run_dhcp_case
[ "$(grep -Fxc 'dnsmasq restart' "$SERVICE_LOG")" -eq 1 ]
grep -Fq 'lan dhcp runtime unavailable' "$HEALTH_LOG"
if ! grep -Fq 'lan dhcp recovered' "$HEALTH_LOG"; then
	echo "FAIL: DHCP recovery was not confirmed" >&2
	cat "$HEALTH_LOG" >&2
	exit 1
fi

# Both runtime signals present means no recovery action is needed.
reset_dhcp_case
printf '%s\n' 'dhcp-range=set:lan,192.168.1.100,192.168.1.249,255.255.255.0,12h' \
	> "$DNSMASQ_CONFIG_FILE"
printf '%s\n' '1: 00000000:0043 00000000:0000 07 00000000:00000000' \
	> "$PROC_NET_UDP"
DHCP_IGNORE=0 run_dhcp_case
if [ -s "$SERVICE_LOG" ]; then
	echo "FAIL: healthy LAN DHCP triggered a restart" >&2
	exit 1
fi

# Explicit UCI disable states are administrator policy, not runtime failures.
for disabled_case in ignore dhcpv4; do
	reset_dhcp_case
	if [ "$disabled_case" = "ignore" ]; then
		DHCP_IGNORE=1 DHCPV4=server run_dhcp_case
	else
		DHCP_IGNORE=0 DHCPV4=disabled run_dhcp_case
	fi
	if [ -s "$SERVICE_LOG" ]; then
		echo "FAIL: intentionally disabled LAN DHCP triggered a restart" >&2
		exit 1
	fi
done

# Persistent failure may restart once, but the cooldown blocks the next run.
reset_dhcp_case
DHCP_IGNORE=0 DNSMASQ_RECOVER=0 run_dhcp_case
DHCP_IGNORE=0 DNSMASQ_RECOVER=0 run_dhcp_case
[ "$(grep -Fxc 'dnsmasq restart' "$SERVICE_LOG")" -eq 1 ]
grep -Fq 'lan dhcp remains unavailable after dnsmasq restart' "$HEALTH_LOG"

HOOK="$ROOT_DIR/files/etc/hotplug.d/iface/99-zn-m2-dhcp-guard"
if [ ! -f "$HOOK" ]; then
	echo "FAIL: LAN DHCP hotplug guard is missing" >&2
	exit 1
fi
cat > "$TMP_DIR/bin/healthcheck" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HOOK_LOG"
EOF
chmod +x "$TMP_DIR/bin/healthcheck"
export HOOK_LOG="$TMP_DIR/evidence/hook.log"
: > "$HOOK_LOG"
ACTION=ifup INTERFACE=lan ZN_M2_HEALTHCHECK="$TMP_DIR/bin/healthcheck" \
	sh "$HOOK"
ACTION=ifdown INTERFACE=lan ZN_M2_HEALTHCHECK="$TMP_DIR/bin/healthcheck" \
	sh "$HOOK"
ACTION=ifup INTERFACE=wan ZN_M2_HEALTHCHECK="$TMP_DIR/bin/healthcheck" \
	sh "$HOOK"
[ "$(wc -l < "$HOOK_LOG")" -eq 1 ]
grep -Fxq -- '--dhcp-only' "$HOOK_LOG"

echo "healthcheck hardening regression tests passed"
