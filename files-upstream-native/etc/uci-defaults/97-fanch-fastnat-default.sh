#!/bin/sh
# FWX ships fastnat disabled, so the stock image routes everything in software.
# The ZN-M2 build exists to exercise the accelerator: enable it once at first
# boot, then leave the administrator's choice alone.
[ -f /etc/config/fastnat ] || exit 0
uci -q set fastnat.global.enabled='1' || exit 0
uci -q commit fastnat
exit 0
