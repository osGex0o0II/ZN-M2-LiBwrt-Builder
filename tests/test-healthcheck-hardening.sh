#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/init.d" "$TMP_DIR/evidence"
SCRIPT="$TMP_DIR/zn-m2-healthcheck"
sed \
	-e "s#^PATH=.*#PATH='$TMP_DIR/bin:/usr/sbin:/usr/bin:/sbin:/bin'#" \
	-e "s#^STATE_DIR=.*#STATE_DIR='$TMP_DIR/state'#" \
	-e "s#/etc/init.d/#$TMP_DIR/init.d/#g" \
	"$ROOT_DIR/files/usr/sbin/zn-m2-healthcheck" > "$SCRIPT"
chmod +x "$SCRIPT"

cat > "$TMP_DIR/bin/ip" <<'EOF'
#!/bin/sh
echo "default via 192.0.2.1 dev eth0"
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
chmod +x "$TMP_DIR/bin/"* "$TMP_DIR/init.d/homeproxy"

export HEALTH_LOG="$TMP_DIR/evidence/health.log"
export SERVICE_LOG="$TMP_DIR/evidence/service.log"
: > "$HEALTH_LOG"
: > "$SERVICE_LOG"

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
mode="$(stat -f '%Lp' "$TMP_DIR/state" 2>/dev/null || stat -c '%a' "$TMP_DIR/state")"
[ "$mode" = 700 ]

echo "healthcheck hardening regression tests passed"
