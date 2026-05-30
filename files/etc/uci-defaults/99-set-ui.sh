#!/bin/sh
# 首次开机强制设置语言为中文，主题为 Aurora
uci set luci.main.lang='zh_cn'
uci set luci.main.mediaurlbase='/luci-static/aurora'
uci commit luci
exit 0
