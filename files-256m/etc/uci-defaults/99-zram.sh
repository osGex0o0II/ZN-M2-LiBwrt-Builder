#!/bin/sh

# Preserve an administrator-selected ZRAM policy across sysupgrade.
if [ "${ZN_M2_CONFIG_RESTORED:-0}" = "1" ] ||
   [ -f /sysupgrade.tgz ] || [ -f /tmp/sysupgrade.tar ]; then
	echo "Preserved configuration detected; skip ZRAM defaults"
	exit 0
fi

# ZRAM swap 压缩算法调优 — 256MB 版本专用。
#
# 使用 lzo-rle；实际压缩率取决于交换页内容，不能按固定倍数折算。
# zram-swap 未显式配置容量时，会按内核可见内存的一半创建交换设备。
#
# 注：zram-swap init 脚本运行前会先检查算法可用性，
# 若内核不支持 lzo-rle 则自动回退。
uci -q set system.@system[0].zram_comp_algo='lzo-rle'
uci commit system

exit 0
