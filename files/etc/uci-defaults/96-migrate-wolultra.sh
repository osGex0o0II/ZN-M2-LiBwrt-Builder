#!/bin/sh
set -eu

TAG="wolultra-migration"
SOURCE_CONFIG="luci-wol"
TARGET_CONFIG="wolultra"
FUNCTIONS_LIB="${WOL_MIGRATION_FUNCTIONS_LIB:-/lib/functions.sh}"
migrated_count=0
skipped_count=0

warn() {
	logger -t "$TAG" -p user.warn -- "$*"
}

if ! uci -q show "$SOURCE_CONFIG" >/dev/null 2>&1; then
	exit 0
fi

if [ "$(uci -q get "$TARGET_CONFIG.migration.stock_wol" 2>/dev/null || true)" = "1" ]; then
	exit 0
fi

# shellcheck disable=SC1090
. "$FUNCTIONS_LIB"

migrate_target() {
	local source_section="$1"
	local name mac iface broadcast password normalized_mac target_section

	config_get name "$source_section" name ""
	config_get mac "$source_section" mac ""
	config_get iface "$source_section" iface "br-lan"
	config_get broadcast "$source_section" broadcast "0"
	config_get password "$source_section" password ""

	if ! printf '%s\n' "$mac" | grep -Eq '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'; then
		warn "Skipping target ${source_section}: invalid MAC address"
		skipped_count=$((skipped_count + 1))
		return 0
	fi

	normalized_mac="$(printf '%s' "$mac" | tr -d ':' | tr '[:upper:]' '[:lower:]')"
	target_section="migrated_${normalized_mac}"
	[ -n "$name" ] || name="$mac"
	[ -n "$iface" ] || iface="br-lan"

	uci -q set "$TARGET_CONFIG.$target_section=macclient"
	uci -q set "$TARGET_CONFIG.$target_section.name=$name"
	uci -q set "$TARGET_CONFIG.$target_section.macaddr=$mac"
	uci -q set "$TARGET_CONFIG.$target_section.maceth=$iface"
	uci -q set "$TARGET_CONFIG.$target_section.scheduled=0"

	if [ -n "$password" ]; then
		warn "Target ${name} used a SecureOn password; WOL Ultra cannot migrate password support"
	fi
	if [ "$broadcast" != "1" ]; then
		warn "Target ${name} did not force broadcast; WOL Ultra always uses etherwake broadcast mode"
	fi

	migrated_count=$((migrated_count + 1))
}

executable="$(uci -q get "$SOURCE_CONFIG.defaults.executable" 2>/dev/null || true)"
case "$executable" in
	*/wakeonlan|wakeonlan)
		warn "The previous default backend was wakeonlan; WOL Ultra always uses etherwake"
		;;
esac

config_load "$SOURCE_CONFIG"
config_foreach migrate_target target

uci -q set "$TARGET_CONFIG.migration=migration"
uci -q set "$TARGET_CONFIG.migration.stock_wol=1"
uci -q set "$TARGET_CONFIG.migration.migrated_count=$migrated_count"
uci -q set "$TARGET_CONFIG.migration.skipped_count=$skipped_count"
uci -q commit "$TARGET_CONFIG"

logger -t "$TAG" -p user.notice -- \
	"Migrated ${migrated_count} stock WOL targets; skipped ${skipped_count}. Original luci-wol config was preserved."

exit 0
