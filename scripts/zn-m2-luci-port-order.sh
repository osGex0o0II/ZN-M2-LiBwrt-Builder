#!/bin/sh
# Put the WAN port first on the LuCI status page.
#
# The panel is rendered from feeds/luci/luci-mod-status and sorts the ports by
# their kernel names, so "wan" always lands last even though the ZN-M2 panel
# prints WAN on the far left. Both upstream layouts are handled:
#   ImmortalWrt / OpenWrt / FanchmWrt -> include/29_ports.js
#   LEDE                              -> include/15_ports.js
# The rewrite is anchored on the sort call and fails closed when the upstream
# text moves, because a silent skip would ship an unpatched panel.
set -eu

tree=${1:?usage: zn-m2-luci-port-order.sh OPENWRT_SOURCE_ROOT}
luci="$tree/feeds/luci"
if [ ! -d "$luci" ]; then
	echo "ERROR: LuCI feed is missing under ${luci}" >&2
	exit 1
fi

# The Windows test hosts expose a Store stub as python3; prefer an interpreter
# that actually runs before falling back.
if [ -n "${PYTHON:-}" ]; then
	python="$PYTHON"
else
	python=""
	for candidate in python3 python; do
		if command -v "$candidate" >/dev/null 2>&1 &&
			"$candidate" -c 'import sys' >/dev/null 2>&1; then
			python="$candidate"
			break
		fi
	done
	[ -n "$python" ] || {
		echo "ERROR: no working Python interpreter found" >&2
		exit 1
	}
fi

exec "$python" - "$luci" <<'PY'
import pathlib
import sys

include = pathlib.Path(sys.argv[1]) / 'modules/luci-mod-status/htdocs/luci-static/resources/view/status/include'
candidates = [include / '29_ports.js', include / '15_ports.js']
present = [path for path in candidates if path.is_file()]

if not present:
    sys.exit('ERROR: no LuCI port-status include found under %s' % include)
if len(present) > 1:
    sys.exit('ERROR: both LuCI port-status layouts are present: %s'
             % ', '.join(path.name for path in present))

path = present[0]
text = path.read_text(encoding='utf-8')
anchor = 'known_ports.sort(function(a, b) {'
marker = 'ZN_M2_WAN_FIRST'

if marker in text:
    print('LuCI port order already patched: %s' % path.name)
    raise SystemExit(0)

found = text.count(anchor)
if found != 1:
    sys.exit('ERROR: expected exactly one %r in %s, found %d'
             % (anchor, path.name, found))

start = text.index(anchor)
line_start = text.rfind('\n', 0, start) + 1
indent = text[line_start:start]
if indent.strip():
    sys.exit('ERROR: unexpected indentation before the port sort in %s' % path.name)

end = text.find('});', start)
if end < 0:
    sys.exit('ERROR: unterminated port sort block in %s' % path.name)
end += len('});')

tab = '\t'
# Keep this a single expression: LuCI pipes the file through the ancient jsmin,
# which handles ternaries and || fine but is fragile around unbraced if bodies.
replacement = (
    anchor + '\n'
    + indent + tab + '/* ' + marker + ': the panel prints WAN on the far left. */\n'
    + indent + tab + "const wan_a = (a.role === 'wan' || a.device === 'wan') ? 0 : 1;\n"
    + indent + tab + "const wan_b = (b.role === 'wan' || b.device === 'wan') ? 0 : 1;\n"
    + indent + tab + 'return (wan_a - wan_b) || L.naturalCompare(a.label || a.device, b.label || b.device);\n'
    + indent + '});'
)

patched = text[:start] + replacement + text[end:]
if patched.count(marker) != 1 or patched.count(anchor) != 1:
    sys.exit('ERROR: patch did not apply cleanly to %s' % path.name)

path.write_text(patched, encoding='utf-8')
print('LuCI port order patched: %s' % path.name)
PY
