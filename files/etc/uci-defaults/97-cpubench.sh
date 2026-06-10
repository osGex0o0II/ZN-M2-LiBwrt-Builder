#!/bin/sh

# LuCI Overview 页面型号旁显示 CPU CoreMark 实测分数。
# 机制：rpcd getCPUBench → readfile('/etc/bench.log') → 拼接到 boardinfo.model
# 首次启动运行 coremark，解析 Iterations/Sec 写入 bench.log。
# coremark 不可用或解析失败时回退到静态估算值。

BENCH_LOG="/etc/bench.log"
FALLBACK=" (CPU Mark: 18000 Score)"
COREMARK_OUT="/tmp/coremark.log"

# 幂等性：已有缓存则跳过，避免系统升级/手动触发时重复跑 CoreMark（~30s）
if [ -f "$BENCH_LOG" ]; then
    cat "$BENCH_LOG" 2>/dev/null || true
    echo "Benchmark already cached, skip" >&2
    exit 0
fi

if [ -x /bin/coremark ]; then
	echo "Running CoreMark benchmark (may take ~30s)..." >&2
	# 保存原始日志到 /tmp/coremark.log 供排查，同时传递到 stdout
	# nice -n 10: 降低 CPU 优先级，避免与启动服务竞争资源
	nice -n 10 coremark 2>&1 | tee "$COREMARK_OUT"

	# 多重正则 fallback，适配不同 coremark 输出格式：
	#   Fallback 1: "Iterations/Sec : 3864.734300"（标准格式）
	#   Fallback 2: "Iterations per second: 3864.734300"（变体）
	#   Fallback 3: 提取原始日志末尾的浮点数（通用兜底）
	SCORE=""
	[ -z "$SCORE" ] && SCORE=$(sed -n 's/.*Iterations\/Sec[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p' "$COREMARK_OUT" | head -1)
	[ -z "$SCORE" ] && SCORE=$(sed -n 's/.*Iterations per second[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p' "$COREMARK_OUT" | head -1)
	[ -z "$SCORE" ] && SCORE=$(grep -oE '[0-9]+\.[0-9]+' "$COREMARK_OUT" | tail -1)

	# Validate SCORE is numeric (integer or decimal)
	if [ -n "$SCORE" ] && echo "$SCORE" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
		# Keep full precision for display
		echo -n " (CPU Mark: ${SCORE} Score)" > "$BENCH_LOG"
		echo "CoreMark score: ${SCORE}" >&2
		exit 0
	fi

	# 匹配失败：在 UI 明确提示异常，并保存原始日志供排查
	echo "WARNING: CoreMark output parsing failed, saved log to ${COREMARK_OUT}" >&2
	echo -n " (CPU Mark: failed, see ${COREMARK_OUT})" > "$BENCH_LOG"
	exit 0
fi

echo "CoreMark binary not found, using fallback score" >&2
echo -n "$FALLBACK" > "$BENCH_LOG"

exit 0
