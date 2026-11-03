#!/bin/sh
# LED sysfs names differ between upstreams: ImmortalWrt labels the ZN-M2 LEDs
# "blue:wan", while LEDE labels them "m2:blue:wan". A config carried across a
# reflash then points at a device that does not exist and /etc/init.d/led
# silently skips it, leaving only the power LED lit.
LEDS_DIR="${ZN_M2_LEDS_DIR:-/sys/class/leds}"

changed=0
for sec in $(uci show system 2>/dev/null | sed -n 's/^system\.\([^.]*\)=led$/\1/p'); do
	sysfs="$(uci -q get "system.$sec.sysfs")"
	[ -n "$sysfs" ] || continue
	[ -e "$LEDS_DIR/$sysfs" ] && continue

	for cand in "$LEDS_DIR/${sysfs#*:}" "$LEDS_DIR"/*:"$sysfs"; do
		[ -e "$cand" ] || continue
		uci set "system.$sec.sysfs=${cand##*/}"
		changed=1
		break
	done
done

[ "$changed" = 1 ] && uci commit system
exit 0
