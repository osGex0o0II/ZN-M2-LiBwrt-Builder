#!/bin/sh
# A config carried across a reflash may name LEDs "blue:wan" while the booted
# upstream exposes "m2:blue:wan" (or the reverse). The normaliser must repoint
# every config led section at a device that actually exists.
set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
script="$repo_root/files-shared/etc/uci-defaults/94-normalize-led-sysfs.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT HUP INT TERM

leds="$workdir/leds"
mkdir -p "$leds/m2:blue:wan" "$leds/m2:blue:lan" "$leds/m2:blue:power"
mkdir -p "$workdir/bin"

cat > "$workdir/bin/uci" <<'EOF'
#!/bin/sh
# Minimal uci stub: records set/commit calls in $UCI_STATE.
state="${UCI_STATE:?}"
cmd="$1"
[ "$cmd" = "-q" ] && { shift; cmd="$1"; }
shift
case "$cmd" in
get)
	case "$1" in
	system.led_wan.sysfs) echo "${LED_WAN:-blue:wan}" ;;
	system.led_lan.sysfs) echo "${LED_LAN:-blue:lan}" ;;
	*) exit 1 ;;
	esac
	;;
show)
	echo "system.led_wan=led"
	echo "system.led_lan=led"
	;;
set)
	echo "$1" >> "$state"
	;;
commit)
	echo "commit" >> "$state"
	;;
esac
EOF
chmod +x "$workdir/bin/uci"

state="$workdir/state"
: > "$state"
PATH="$workdir/bin:$PATH" UCI_STATE="$state" ZN_M2_LEDS_DIR="$leds" sh "$script"

grep -qx 'system.led_wan.sysfs=m2:blue:wan' "$state" || {
	echo "FAIL: wan LED not repointed" >&2
	cat "$state" >&2
	exit 1
}
grep -qx 'system.led_lan.sysfs=m2:blue:lan' "$state" || {
	echo "FAIL: lan LED not repointed" >&2
	cat "$state" >&2
	exit 1
}
grep -qx 'commit' "$state" || {
	echo "FAIL: uci commit not called" >&2
	exit 1
}

# Already-correct names must not be rewritten or committed.
rm -rf "$leds"
mkdir -p "$leds/blue:wan" "$leds/blue:lan"
: > "$state"
PATH="$workdir/bin:$PATH" UCI_STATE="$state" ZN_M2_LEDS_DIR="$leds" LED_WAN='blue:wan' LED_LAN='blue:lan' sh "$script"
[ -s "$state" ] && { echo "FAIL: rewrote an already valid config" >&2; cat "$state" >&2; exit 1; }

# The reverse drift (config with the vendor prefix, image without) must also fix up.
rm -rf "$leds"
mkdir -p "$leds/blue:wan" "$leds/blue:lan"
: > "$state"
PATH="$workdir/bin:$PATH" UCI_STATE="$state" ZN_M2_LEDS_DIR="$leds" LED_WAN='m2:blue:wan' LED_LAN='m2:blue:lan' sh "$script"
grep -qx 'system.led_wan.sysfs=blue:wan' "$state" || {
	echo "FAIL: reverse drift not repaired" >&2
	cat "$state" >&2
	exit 1
}

echo "led sysfs normalization test passed"
