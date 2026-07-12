#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
COMMON_MIGRATION="$ROOT_DIR/files/etc/uci-defaults/95-upgrade-security-migration.sh"
DNS_MIGRATION="$ROOT_DIR/files-256m/etc/uci-defaults/95-upgrade-dns-migration.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

if [ ! -x "$COMMON_MIGRATION" ] || [ ! -x "$DNS_MIGRATION" ]; then
	echo "FAIL: upgrade migration scripts are missing" >&2
	exit 1
fi

mkdir -p "$TMP_DIR/bin"
UCI_LOG="$TMP_DIR/uci.log"
export UCI_LOG

cat > "$TMP_DIR/bin/uci" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$UCI_LOG"

if [ "${1:-}" = "-q" ] && [ "${2:-}" = "show" ] && [ "${3:-}" = "firewall" ]; then
	if [ -n "${FIREWALL_SHOW_FILE:-}" ] && [ -f "$FIREWALL_SHOW_FILE" ]; then
		cat "$FIREWALL_SHOW_FILE"
	fi
	exit 0
fi

if [ "${1:-}" = "-q" ] && [ "${2:-}" = "get" ]; then
	case "${3:-}" in
		dhcp.@dnsmasq\[0\].noresolv) printf '%s\n' "${DNS_NORESOLV:-}" ;;
		dhcp.@dnsmasq\[0\].server) printf '%s\n' "${DNS_SERVERS:-}" ;;
		*) exit 1 ;;
	esac
fi
EOF
chmod +x "$TMP_DIR/bin/uci"

OLD_HASH="\$6\$znm2default\$nwo/WFy57vlrCL6TiFnP2Oi8qXUY70Q7ZK6H3FXrvE.gNPHToM/8vtpUZSEDNUdHiJl/z3kQqVBLkAzIIFglM0"
SHADOW_FILE="$TMP_DIR/shadow"
printf 'root:%s:0:0:99999:7:::\n' "$OLD_HASH" > "$SHADOW_FILE"
: > "$UCI_LOG"

ZN_M2_CONFIG_RESTORED=1 \
ZN_M2_BOARD_NAME='zn,m2' \
ZN_M2_SHADOW_FILE="$SHADOW_FILE" \
PATH="$TMP_DIR/bin:$PATH" \
	sh "$COMMON_MIGRATION"

grep -Fxq 'root::0:0:99999:7:::' "$SHADOW_FILE"
for rule in zn_m2_allow_mld zn_m2_allow_icmpv6_input zn_m2_allow_icmpv6_forward; do
	grep -Fq -- "-q set firewall.${rule}=rule" "$UCI_LOG"
done
grep -Fq -- '-q commit firewall' "$UCI_LOG"

CUSTOM_HASH="\$6\$custom\$not-the-public-password"
printf 'root:%s:0:0:99999:7:::\n' "$CUSTOM_HASH" > "$SHADOW_FILE"
FIREWALL_SHOW_FILE="$TMP_DIR/firewall.show"
export FIREWALL_SHOW_FILE
printf '%s\n' \
	"firewall.cfg01.name='Allow-MLD'" \
	"firewall.cfg02.name='Allow-ICMPv6-Input'" \
	"firewall.cfg03.name='Allow-ICMPv6-Forward'" > "$FIREWALL_SHOW_FILE"
: > "$UCI_LOG"
ZN_M2_CONFIG_RESTORED=1 \
ZN_M2_BOARD_NAME='zn,m2' \
ZN_M2_SHADOW_FILE="$SHADOW_FILE" \
PATH="$TMP_DIR/bin:$PATH" \
	sh "$COMMON_MIGRATION"
grep -Fxq "root:${CUSTOM_HASH}:0:0:99999:7:::" "$SHADOW_FILE"
if grep -Fq 'set firewall.zn_m2_' "$UCI_LOG"; then
	echo "FAIL: complete existing IPv6 policy was duplicated" >&2
	exit 1
fi

: > "$UCI_LOG"
DNS_NORESOLV=1 DNS_SERVERS='223.5.5.5 119.29.29.29' \
ZN_M2_CONFIG_RESTORED=1 PATH="$TMP_DIR/bin:$PATH" \
	sh "$DNS_MIGRATION"
grep -Fq -- "-q set dhcp.@dnsmasq[0].noresolv=0" "$UCI_LOG"
grep -Fq -- "-q delete dhcp.@dnsmasq[0].server" "$UCI_LOG"

: > "$UCI_LOG"
DNS_NORESOLV=1 DNS_SERVERS='223.5.5.5 119.29.29.29 1.1.1.1' \
ZN_M2_CONFIG_RESTORED=1 PATH="$TMP_DIR/bin:$PATH" \
	sh "$DNS_MIGRATION"
if grep -Eq '(set|delete) dhcp\\.@dnsmasq' "$UCI_LOG"; then
	echo "FAIL: custom DNS policy was modified" >&2
	exit 1
fi

echo "upgrade migration regression tests passed"
