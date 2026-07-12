#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
mkdir -p "$TMP_DIR/bin"

SCRIPT="$TMP_DIR/97-cpubench.sh"
sed \
	-e "s#^BENCH_LOG=.*#BENCH_LOG='$TMP_DIR/bench.log'#" \
	-e "s#^COREMARK_OUT=.*#COREMARK_OUT='$TMP_DIR/coremark.log'#" \
	"$ROOT_DIR/files/etc/uci-defaults/97-cpubench.sh" > "$SCRIPT"

cat > "$TMP_DIR/bin/coremark" <<'EOF'
#!/bin/sh
echo "CoreMark validation failed; diagnostic ratio 12.34"
exit 1
EOF
chmod +x "$TMP_DIR/bin/coremark"
PATH="$TMP_DIR/bin:$PATH" sh "$SCRIPT" >/dev/null 2>&1
if grep -Fq 'CPU Mark: 12.34 Score' "$TMP_DIR/bench.log"; then
	echo "FAIL: failed CoreMark diagnostic was accepted as a score" >&2
	exit 1
fi

rm -f "$TMP_DIR/bench.log"
cat > "$TMP_DIR/bin/coremark" <<'EOF'
#!/bin/sh
echo "Iterations/Sec : 3864.734300"
echo "Correct operation validated. See README.md for run and reporting rules."
exit 0
EOF
chmod +x "$TMP_DIR/bin/coremark"
PATH="$TMP_DIR/bin:$PATH" sh "$SCRIPT" >/dev/null 2>&1
grep -Fq 'CPU Mark: 3864.734300 Score' "$TMP_DIR/bench.log"

echo "CoreMark hardening regression tests passed"
