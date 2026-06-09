#!/bin/sh

# LuCI Overview 页面型号旁显示 CPU CoreMark 实测分数。
# 机制：rpcd getCPUBench → readfile('/etc/bench.log') → 拼接到 boardinfo.model
# 首次启动运行 coremark，解析 Iterations/Sec 写入 bench.log。
# coremark 不可用时回退到静态估算值。

BENCH_LOG="/etc/bench.log"
FALLBACK=" (CPU Mark: 18000 Score)"

if [ -x /bin/coremark ]; then
	echo "Running CoreMark benchmark (may take ~30s)..." >&2
	SCORE=$(coremark 2>&1 | sed -n 's/.*Iterations\/Sec[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p' | cut -d. -f1)

	if [ -n "$SCORE" ] && [ "$SCORE" -gt 0 ] 2>/dev/null; then
		echo -n " (CPU Mark: ${SCORE} Score)" > "$BENCH_LOG"
		echo "CoreMark score: ${SCORE}" >&2
		exit 0
	fi
fi

echo "CoreMark not found or failed, using fallback score" >&2
echo -n "$FALLBACK" > "$BENCH_LOG"

exit 0
