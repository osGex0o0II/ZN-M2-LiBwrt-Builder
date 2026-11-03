#!/bin/sh
# The DHCP primer must produce a LAN range even when the upstream ipcalc.sh
# rejects "address/dotted-netmask" (LEDE) and falls back to 0.0.0.0/0.
set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
primer="$repo_root/files/etc/init.d/zn-m2-dhcp-primer"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT HUP INT TERM

mkdir -p "$workdir/bin"
cat > "$workdir/bin/uci" <<'EOF'
#!/bin/sh
# Minimal uci stub: uci -q get <key>
[ "$1" = "-q" ] && shift
[ "$1" = "get" ] && shift
case "$1" in
network.lan.proto) echo static ;;
network.lan.ipaddr) echo 192.168.10.1 ;;
network.lan.netmask) echo 255.255.255.0 ;;
"dhcp.@dnsmasq[0].confdir") echo /etc/dnsmasq.d ;;
dhcp.lan.start) echo 100 ;;
dhcp.lan.limit) echo 150 ;;
dhcp.lan.leasetime) echo 12h ;;
esac
EOF
chmod +x "$workdir/bin/uci"

# LEDE ipcalc: only "address/prefix" parses; "address/dotted" yields 0.0.0.x.
cat > "$workdir/lede-ipcalc" <<'EOF'
#!/bin/sh
case "$1" in
*.*.*.*/*.*.*.*) ip=0.0.0.1; mask=0.0.0.0; prefix=16 ;;
*) ip="${1%%/*}"; mask=255.255.255.0; prefix=24 ;;
esac
net="$(echo "$ip" | cut -d. -f1-3)"
echo "IP=$ip"
echo "NETMASK=$mask"
echo "PREFIX=$prefix"
echo "START=$net.100"
echo "END=$net.250"
EOF
chmod +x "$workdir/lede-ipcalc"

out="$workdir/primer.conf"
rm -f "$out"
PATH="$workdir/bin:$PATH" \
ZN_M2_DHCP_PRIMER_FILE="$out" \
ZN_M2_IPCALC="$workdir/lede-ipcalc" \
	sh -c '. "$1"; write_primer' sh "$primer"

[ -f "$out" ] || { echo "FAIL: primer not written" >&2; exit 1; }
got="$(cat "$out")"
want="dhcp-range=set:lan,192.168.10.100,192.168.10.250,255.255.255.0,12h"
[ "$got" = "$want" ] || {
	echo "FAIL: primer range mismatch" >&2
	echo "  got:  $got" >&2
	echo "  want: $want" >&2
	exit 1
}

# A range outside the LAN subnet must be dropped, never primed.
cat > "$workdir/bad-ipcalc" <<'EOF'
#!/bin/sh
echo "IP=192.168.10.1"
echo "NETMASK=255.255.255.0"
echo "PREFIX=24"
echo "START=0.0.0.100"
echo "END=0.0.0.250"
EOF
chmod +x "$workdir/bad-ipcalc"

rm -f "$out"
PATH="$workdir/bin:$PATH" \
ZN_M2_DHCP_PRIMER_FILE="$out" \
ZN_M2_IPCALC="$workdir/bad-ipcalc" \
	sh -c '. "$1"; write_primer' sh "$primer"
[ ! -f "$out" ] || {
	echo "FAIL: out-of-subnet range was primed: $(cat "$out")" >&2
	exit 1
}

echo "dhcp primer ipcalc regression test passed"
