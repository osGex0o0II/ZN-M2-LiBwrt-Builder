#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
PRIMER="$ROOT_DIR/files/etc/init.d/zn-m2-dhcp-primer"
CLEANUP="$ROOT_DIR/files/etc/init.d/zn-m2-dhcp-primer-cleanup"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
mkdir -p "$TMP_DIR/bin" "$TMP_DIR/dnsmasq.d"

cat > "$TMP_DIR/bin/uci" <<'EOF'
#!/bin/sh
case "$*" in
	"-q get dhcp.@dnsmasq[0].confdir") printf '%s\n' "${CONFDIR-/etc/dnsmasq.d}" ;;
	"-q get network.lan.proto") printf '%s\n' "${PROTO:-static}" ;;
	"-q get network.lan.ipaddr") printf '%s\n' "${IPADDR:-192.168.10.1}" ;;
	"-q get network.lan.netmask") printf '%s\n' "${NETMASK:-255.255.255.0}" ;;
	"-q get dhcp.lan.ignore") printf '%s\n' "${DHCP_IGNORE:-0}" ;;
	"-q get dhcp.lan.dhcpv4") printf '%s\n' "${DHCPV4:-server}" ;;
	"-q get dhcp.lan.start") printf '%s\n' "${START:-100}" ;;
	"-q get dhcp.lan.limit") printf '%s\n' "${LIMIT:-150}" ;;
	"-q get dhcp.lan.leasetime") printf '%s\n' "${LEASE:-12h}" ;;
	"-q get dhcp.lan.networkid") printf '%s\n' "${NETWORKID:-lan}" ;;
	"-q get dhcp.lan.dynamicdhcpv4") printf '%s\n' "${DYNAMIC:-1}" ;;
	"-q get dhcp.lan.dynamicdhcp") printf '%s\n' "${DYNAMIC:-1}" ;;
	*) exit 1 ;;
esac
EOF
chmod +x "$TMP_DIR/bin/uci"

cat > "$TMP_DIR/bin/ipcalc" <<'EOF'
#!/bin/sh
printf '%s\n' \
	'START=192.168.10.100' \
	'END=192.168.10.249' \
	'NETMASK=255.255.255.0'
EOF
chmod +x "$TMP_DIR/bin/ipcalc"

run_primer() {
	env \
		PATH="$TMP_DIR/bin:$PATH" \
		ZN_M2_IPCALC="$TMP_DIR/bin/ipcalc" \
		ZN_M2_DHCP_PRIMER_FILE="$TMP_DIR/dnsmasq.d/00-zn-m2-lan.conf" \
		"$@" \
		sh -c '. "$1"; start' sh "$PRIMER"
}

FILE="$TMP_DIR/dnsmasq.d/00-zn-m2-lan.conf"
run_primer
grep -Fxq 'dhcp-range=set:lan,192.168.10.100,192.168.10.249,255.255.255.0,12h' "$FILE"

rm -f "$FILE"
PROTO=dhcp DYNAMIC=1 run_primer
[ ! -e "$FILE" ]

rm -f "$FILE"
DHCP_IGNORE=1 run_primer
[ ! -e "$FILE" ]

rm -f "$FILE"
DHCPV4=disabled run_primer
[ ! -e "$FILE" ]

rm -f "$FILE"
DYNAMIC=0 run_primer
grep -Fxq 'dhcp-range=set:lan,192.168.10.100,static,255.255.255.0,12h' "$FILE"

rm -f "$FILE"
CONFDIR=/tmp/custom-dnsmasq-dir run_primer
[ ! -e "$FILE" ]

run_primer
[ -e "$FILE" ]
env PATH="$TMP_DIR/bin:$PATH" \
	ZN_M2_DHCP_PRIMER_FILE="$FILE" \
	sh -c '. "$1"; start' sh "$CLEANUP"
[ ! -e "$FILE" ]

echo "DHCP primer regression tests passed"
