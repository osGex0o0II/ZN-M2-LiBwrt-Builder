#!/bin/sh

# LuCI Overview 页面型号旁显示 CPU Mark 静态分数。
# 机制：rpcd getCPUBench → readfile('/etc/bench.log') → 拼接到 boardinfo.model
# IPQ6000: 4× Cortex-A53 @ 1.512GHz → PassMark CPU Mark ≈ 340

echo -n ' (CPU Mark: 340)' > /etc/bench.log

exit 0
