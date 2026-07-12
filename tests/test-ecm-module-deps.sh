#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
VERIFY="$ROOT_DIR/tests/verify-ecm-module-deps.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

module="$TMP_DIR/ecm.ko"
cat > "$module" <<'EOF'
depends=qca-nss-drv,nf_conntrack,pptp,l2tp_ppp,ppp_generic,pppoe
EOF

"$VERIFY" "$module" required-only > "$TMP_DIR/required.out"
grep -Fq 'ecm.ko dependencies verified' "$TMP_DIR/required.out"

if "$VERIFY" "$module" pppoe-only > "$TMP_DIR/pppoe.out" 2>&1; then
	echo "FAIL: PPPoE-only profile accepted PPTP/L2TP dependencies" >&2
	exit 1
fi
grep -Fq 'forbidden tunnel module: pptp' "$TMP_DIR/pppoe.out"

cat > "$module" <<'EOF'
depends=qca-nss-drv,nf_conntrack,l2tp_ppp,ppp_generic,pppoe
EOF
if "$VERIFY" "$module" pppoe-only > "$TMP_DIR/l2tp.out" 2>&1; then
	echo "FAIL: PPPoE-only profile accepted an L2TP dependency" >&2
	exit 1
fi
grep -Fq 'forbidden tunnel module: l2tp_ppp' "$TMP_DIR/l2tp.out"

cat > "$module" <<'EOF'
depends=qca-nss-drv,nf_conntrack,pptp,ppp_generic
EOF
if "$VERIFY" "$module" required-only > "$TMP_DIR/missing.out" 2>&1; then
	echo "FAIL: required-only profile accepted missing PPPoE dependencies" >&2
	exit 1
fi
grep -Fq 'lost required PPPoE dependency: pppoe' "$TMP_DIR/missing.out"

cat > "$module" <<'EOF'
depends=qca-nss-drv,nf_conntrack,ppp_generic,pppoe
EOF
"$VERIFY" "$module" > "$TMP_DIR/default.out"
grep -Fq 'ecm.ko dependencies verified' "$TMP_DIR/default.out"

if "$VERIFY" "$module" unsupported > "$TMP_DIR/profile.out" 2>&1; then
	echo "FAIL: unsupported ECM dependency profile was accepted" >&2
	exit 1
fi
grep -Fq 'usage:' "$TMP_DIR/profile.out"

echo "ECM module dependency profile tests passed"
