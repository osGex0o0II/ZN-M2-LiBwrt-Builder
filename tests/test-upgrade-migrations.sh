#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
COMMON_MIGRATION="$ROOT_DIR/files/etc/uci-defaults/95-upgrade-security-migration.sh"
DNS_MIGRATION="$ROOT_DIR/files-zn-m2/etc/uci-defaults/95-upgrade-dns-migration.sh"
RUNTIME_MIGRATION="$ROOT_DIR/files-zn-m2/etc/uci-defaults/96-upgrade-runtime-migration.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

if [ ! -x "$COMMON_MIGRATION" ] || [ ! -x "$DNS_MIGRATION" ] ||
   [ ! -x "$RUNTIME_MIGRATION" ]; then
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
		zerotier.global.enabled) printf '%s\n' "${ZEROTIER_ENABLED:-1}" ;;
		upnpd.config.enabled) printf '%s\n' "${UPNPD_ENABLED:-1}" ;;
		system.@system\[0\].zram_comp_algo) printf '%s\n' "${ZRAM_ALGO:-}" ;;
		firewall.@zone\[0\]) echo zone ;;
		firewall.@zone\[0\].name) echo lan ;;
		firewall.@zone\[1\]) echo zone ;;
		firewall.@zone\[1\].name) echo wan ;;
		firewall.@zone\[2\]) exit 1 ;;
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
grep -Fq -- "-q set dhcp.@dnsmasq[0].dnsforwardmax=300" "$UCI_LOG"
grep -Fq -- "-q delete dhcp.@dnsmasq[0].server" "$UCI_LOG"

: > "$UCI_LOG"
DNS_NORESOLV=1 DNS_SERVERS='223.5.5.5 119.29.29.29 1.1.1.1' \
ZN_M2_CONFIG_RESTORED=1 PATH="$TMP_DIR/bin:$PATH" \
	sh "$DNS_MIGRATION"
if grep -Eq '(set|delete) dhcp\.@dnsmasq' "$UCI_LOG"; then
	echo "FAIL: custom DNS policy was modified" >&2
	exit 1
fi

# Runtime migration for preserved configurations: cron, NSS offload, and
# disabled service hooks must be repaired on upgrade, not only on fresh flash.
# A partially deleted IPv6 policy must be repaired one rule at a time.
: > "$UCI_LOG"
printf '%s\n' "firewall.cfg01.name='Allow-MLD'" > "$FIREWALL_SHOW_FILE"
ZN_M2_CONFIG_RESTORED=1 \
ZN_M2_BOARD_NAME='zn,m2' \
ZN_M2_SHADOW_FILE="$SHADOW_FILE" \
PATH="$TMP_DIR/bin:$PATH" \
	sh "$COMMON_MIGRATION"
grep -Fq -- '-q set firewall.zn_m2_allow_icmpv6_input=rule' "$UCI_LOG"
grep -Fq -- '-q set firewall.zn_m2_allow_icmpv6_forward=rule' "$UCI_LOG"

RUNTIME_DIR="$TMP_DIR/runtime"
mkdir -p "$RUNTIME_DIR/config" "$RUNTIME_DIR/init.d"
: > "$RUNTIME_DIR/config/ecm"
for svc in cron zerotier miniupnpd; do
	cat > "$RUNTIME_DIR/init.d/$svc" <<EOF
#!/bin/sh
printf '%s %s\n' "$svc" "\$1" >> "$RUNTIME_DIR/init.log"
exit 0
EOF
	chmod +x "$RUNTIME_DIR/init.d/$svc"
done
CRON_FILE="$RUNTIME_DIR/crontab"
printf '%s\n' \
	'# keep this line' \
	'*/10 * * * * MIN_MEM_KB=32768 COOLDOWN_SEC=600 /usr/sbin/zn-m2-healthcheck >/dev/null 2>&1' > "$CRON_FILE"
printf '%s' '0 4 * * * /etc/coremark.sh' >> "$CRON_FILE"

: > "$UCI_LOG"
: > "$RUNTIME_DIR/init.log"
ZN_M2_CONFIG_RESTORED=1 \
ZN_M2_CONFIG_DIR="$RUNTIME_DIR/config" \
ZN_M2_INIT_DIR="$RUNTIME_DIR/init.d" \
ZN_M2_CRON_FILE="$CRON_FILE" \
ZEROTIER_ENABLED=0 UPNPD_ENABLED=0 ZRAM_ALGO=lzo \
PATH="$TMP_DIR/bin:$PATH" \
	sh "$RUNTIME_MIGRATION"

grep -Fxc '*/10 * * * * MIN_MEM_KB=40960 COOLDOWN_SEC=900 /usr/sbin/zn-m2-healthcheck >/dev/null 2>&1' "$CRON_FILE" >/dev/null
if grep -Fq 'MIN_MEM_KB=32768' "$CRON_FILE"; then
	echo "FAIL: old healthcheck cron line was not replaced" >&2
	exit 1
fi
[ "$(wc -l < "$CRON_FILE")" -eq 3 ] ||
	{
		echo "FAIL: cron file was not normalized to newline-terminated entries" >&2
		exit 1
	}
grep -Fq -- '-q set firewall.@defaults[0].flow_offloading=0' "$UCI_LOG"
grep -Fq -- '-q set firewall.@defaults[0].flow_offloading_hw=0' "$UCI_LOG"
grep -Fq -- '-q set firewall.@zone[1].fullcone=0' "$UCI_LOG"
grep -Fq -- '-q set firewall.@zone[1].fullcone6=0' "$UCI_LOG"
grep -Fq -- '-q commit firewall' "$UCI_LOG"
grep -Fq -- '-q set system.@system[0].zram_comp_algo=lzo-rle' "$UCI_LOG"
grep -Fq 'cron enable' "$RUNTIME_DIR/init.log"
grep -Fq 'cron restart' "$RUNTIME_DIR/init.log"
grep -Fq 'zerotier disable' "$RUNTIME_DIR/init.log"
grep -Fq 'miniupnpd disable' "$RUNTIME_DIR/init.log"

# The PPE variant carries no ECM config, so the NSS-only offload reset must not
# run there: PPE enables hardware flow offload by default.
rm -f "$RUNTIME_DIR/config/ecm"
: > "$UCI_LOG"
ZN_M2_CONFIG_RESTORED=1 \
ZN_M2_CONFIG_DIR="$RUNTIME_DIR/config" \
ZN_M2_INIT_DIR="$RUNTIME_DIR/init.d" \
ZN_M2_CRON_FILE="$CRON_FILE" \
PATH="$TMP_DIR/bin:$PATH" \
	sh "$RUNTIME_MIGRATION"
if grep -Fq 'firewall.@defaults[0].flow_offloading' "$UCI_LOG"; then
	echo "FAIL: the NSS-only offload reset ran without an ECM config" >&2
	exit 1
fi
: > "$RUNTIME_DIR/config/ecm"

# An explicit non-default ZRAM algorithm must be left alone.
: > "$UCI_LOG"
ZN_M2_CONFIG_RESTORED=1 \
ZN_M2_CONFIG_DIR="$RUNTIME_DIR/config" \
ZN_M2_INIT_DIR="$RUNTIME_DIR/init.d" \
ZN_M2_CRON_FILE="$CRON_FILE" \
ZRAM_ALGO=zstd \
PATH="$TMP_DIR/bin:$PATH" \
	sh "$RUNTIME_MIGRATION"
if grep -Fq -- '-q set system.@system[0].zram_comp_algo' "$UCI_LOG"; then
	echo "FAIL: an explicit ZRAM algorithm was overwritten" >&2
	exit 1
fi

# Fresh installs are handled by the normal uci-defaults scripts.
: > "$UCI_LOG"
ZN_M2_CONFIG_RESTORED=0 \
ZN_M2_CONFIG_DIR="$RUNTIME_DIR/config" \
ZN_M2_INIT_DIR="$RUNTIME_DIR/init.d" \
ZN_M2_CRON_FILE="$CRON_FILE" \
PATH="$TMP_DIR/bin:$PATH" \
	sh "$RUNTIME_MIGRATION"
if grep -Fq 'firewall.@defaults' "$UCI_LOG"; then
	echo "FAIL: fresh-install config was changed by the upgrade migration" >&2
	exit 1
fi

echo "upgrade migration regression tests passed"
