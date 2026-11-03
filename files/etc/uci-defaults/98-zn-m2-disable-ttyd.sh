#!/bin/sh
# ttyd exposes a root web terminal on the LAN. Keep it available but off by
# default; the administrator enables it explicitly when needed.
[ -f /etc/config/ttyd ] || exit 0
uci -q set ttyd.@ttyd[0].enabled='0'
uci -q commit ttyd
exit 0
