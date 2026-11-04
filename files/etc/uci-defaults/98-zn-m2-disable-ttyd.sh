#!/bin/sh
# ttyd exposes a root web terminal on the LAN. Keep it available but off by
# default. Seed the default once per install so a later explicit choice in
# LuCI is not silently reverted on the next image upgrade.
[ -f /etc/config/ttyd ] || exit 0
[ "$(uci -q get zn-m2.settings.ttyd_seeded 2>/dev/null)" = "1" ] && exit 0
uci -q set ttyd.@ttyd[0].enabled='0'
uci -q set zn-m2.settings.ttyd_seeded='1'
uci -q commit ttyd
uci -q commit zn-m2 2>/dev/null || true
exit 0
