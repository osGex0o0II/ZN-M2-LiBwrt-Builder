#!/usr/bin/env bash
# The status panel sorts ports by kernel name, so "wan" lands last even though
# the ZN-M2 prints WAN on the far left. Both upstream layouts must be rewritten
# in place, and the rewrite must stay idempotent.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
script="$repo/scripts/zn-m2-luci-port-order.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

include=modules/luci-mod-status/htdocs/luci-static/resources/view/status/include

make_tree() {
	tree="$1"
	file="$2"
	sort_expr="$3"
	mkdir -p "$tree/feeds/luci/$include"
	cat > "$tree/feeds/luci/$include/$file" <<EOF
'use strict';
return baseclass.extend({
	render(data) {
		let known_ports = [];

		known_ports.sort(function(a, b) {
			return L.naturalCompare($sort_expr);
		});

		return known_ports;
	}
});
EOF
}

for case in '29_ports.js|a.device, b.device' '15_ports.js|a.label || a.device, b.label || b.device'; do
	file=${case%%|*}
	expr=${case#*|}
	tree="$fixture/$file"
	make_tree "$tree" "$file" "$expr"
	bash "$script" "$tree" >/dev/null
	js="$tree/feeds/luci/$include/$file"
	grep -Fq 'ZN_M2_WAN_FIRST' "$js"
	grep -Fq "const wan_a = (a.role === 'wan' || a.device === 'wan') ? 0 : 1;" "$js"
	grep -Fq 'return (wan_a - wan_b) || L.naturalCompare(a.label || a.device, b.label || b.device);' "$js"
	# Ordering must be evaluated before the name comparison, otherwise WAN
	# still trails; a single expression keeps jsmin happy during minification.
	[ "$(grep -c 'wan_a - wan_b' "$js")" -eq 1 ]
	before=$(sha256sum < "$js")
	bash "$script" "$tree" >/dev/null
	[ "$before" = "$(sha256sum < "$js")" ]
done

# A tree without the LuCI feed, or without either include, must fail loudly:
# a silent skip would ship a panel that still puts WAN last.
if bash "$script" "$fixture" >/dev/null 2>&1; then
	echo 'FAIL: missing LuCI feed was accepted' >&2
	exit 1
fi

empty="$fixture/empty"
mkdir -p "$empty/feeds/luci/$include"
if bash "$script" "$empty" >/dev/null 2>&1; then
	echo 'FAIL: missing port-status include was accepted' >&2
	exit 1
fi

echo 'PASS: WAN first on both LuCI layouts, idempotent, fails closed'
