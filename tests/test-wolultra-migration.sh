#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
MIGRATION="$ROOT_DIR/files/etc/uci-defaults/96-migrate-wolultra.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

if [ ! -x "$MIGRATION" ]; then
	echo "FAIL: WOL Ultra migration script is missing" >&2
	exit 1
fi

mkdir -p "$TMP_DIR/bin"
UCI_LOG="$TMP_DIR/uci.log"
LOGGER_LOG="$TMP_DIR/logger.log"
export UCI_LOG LOGGER_LOG

cat > "$TMP_DIR/functions.sh" <<'EOF'
config_load() {
	[ "$1" = "luci-wol" ]
}

config_foreach() {
	callback="$1"
	type="$2"
	[ "$type" = "target" ]
	"$callback" good_target
	"$callback" invalid_target
}

config_get() {
	variable="$1"
	section="$2"
	option="$3"
	default="${4:-}"
	value="$default"
	case "$section:$option" in
		good_target:name) value='Office PC' ;;
		good_target:mac) value='AA:BB:CC:DD:EE:FF' ;;
		good_target:iface) value='br-lan' ;;
		good_target:broadcast) value='0' ;;
		good_target:password) value='00:11:22:33:44:55' ;;
		invalid_target:mac) value='not-a-mac' ;;
	esac
	eval "$variable=\$value"
}
EOF

cat > "$TMP_DIR/bin/uci" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$UCI_LOG"

if [ "${1:-}" = "-q" ] && [ "${2:-}" = "show" ] && [ "${3:-}" = "luci-wol" ]; then
	exit 0
fi
if [ "${1:-}" = "-q" ] && [ "${2:-}" = "get" ]; then
	case "${3:-}" in
		wolultra.migration.stock_wol)
			[ "${MIGRATION_DONE:-0}" = "1" ] && echo 1 && exit 0
			exit 1
			;;
		luci-wol.defaults.executable)
			echo /usr/bin/wakeonlan
			exit 0
			;;
	esac
fi
exit 0
EOF

cat > "$TMP_DIR/bin/logger" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$LOGGER_LOG"
EOF
chmod +x "$TMP_DIR/bin/uci" "$TMP_DIR/bin/logger"

PATH="$TMP_DIR/bin:$PATH" \
	WOL_MIGRATION_FUNCTIONS_LIB="$TMP_DIR/functions.sh" \
	sh "$MIGRATION"

for expected in \
	'-q set wolultra.migrated_aabbccddeeff=macclient' \
	'-q set wolultra.migrated_aabbccddeeff.name=Office PC' \
	'-q set wolultra.migrated_aabbccddeeff.macaddr=AA:BB:CC:DD:EE:FF' \
	'-q set wolultra.migrated_aabbccddeeff.maceth=br-lan' \
	'-q set wolultra.migrated_aabbccddeeff.scheduled=0' \
	'-q set wolultra.migration=migration' \
	'-q set wolultra.migration.stock_wol=1' \
	'-q commit wolultra'; do
	grep -Fxq -- "$expected" "$UCI_LOG" || {
		echo "FAIL: missing migration operation: $expected" >&2
		exit 1
	}
done

if grep -Fq 'not-a-mac' "$UCI_LOG"; then
	echo 'FAIL: invalid MAC was migrated' >&2
	exit 1
fi
grep -Fqi 'wakeonlan' "$LOGGER_LOG"
grep -Fqi 'password' "$LOGGER_LOG"
grep -Fqi 'broadcast' "$LOGGER_LOG"

: > "$UCI_LOG"
MIGRATION_DONE=1 \
	PATH="$TMP_DIR/bin:$PATH" \
	WOL_MIGRATION_FUNCTIONS_LIB="$TMP_DIR/functions.sh" \
	sh "$MIGRATION"
if grep -Fq ' set ' "$UCI_LOG"; then
	echo 'FAIL: completed migration was not idempotent' >&2
	exit 1
fi

echo "WOL Ultra migration tests passed"
