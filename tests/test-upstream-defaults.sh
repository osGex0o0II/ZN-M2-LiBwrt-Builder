#!/bin/sh
set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
source_root="${1:-${OPENWRT_SOURCE_DIR:-}}"
relative_script="target/linux/qualcommax/base-files/etc/uci-defaults/991_set-network.sh"
patch_file="$repo_root/patches/qualcommax/preserve-network-settings.patch"
expected_sha256="da8f39e259d537f2feb2522503fa2b408824f335f84bdf619d8ea11eed33eec0"

if [ -z "$source_root" ] || [ ! -f "$source_root/$relative_script" ]; then
	echo "usage: $0 /path/to/openwrt" >&2
	exit 2
fi

actual_sha256="$(sha256sum "$source_root/$relative_script" | awk '{print $1}')"
if [ "$actual_sha256" != "$expected_sha256" ]; then
	echo "upstream 991_set-network.sh changed: ${actual_sha256}" >&2
	exit 1
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT HUP INT TERM
mkdir -p "$workdir/$(dirname "$relative_script")" "$workdir/bin"
cp "$source_root/$relative_script" "$workdir/$relative_script"
git -C "$workdir" init -q
git -C "$workdir" apply --check "$patch_file"
git -C "$workdir" apply "$patch_file"

uci_log="$workdir/uci.log"
export UCI_LOG="$uci_log"
cat > "$workdir/bin/uci" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$UCI_LOG"
if [ "${1:-}" = "get" ] && [ "${2:-}" = "network.globals.ula_prefix" ]; then
	echo 'fd00:1234::/48'
fi
EOF
chmod +x "$workdir/bin/uci"

: > "$uci_log"
ZN_M2_CONFIG_RESTORED=1 PATH="$workdir/bin:$PATH" \
	sh "$workdir/$relative_script" >/dev/null
if [ -s "$uci_log" ]; then
	echo "qualcommax defaults changed preserved network configuration" >&2
	cat "$uci_log" >&2
	exit 1
fi

: > "$uci_log"
PATH="$workdir/bin:$PATH" sh "$workdir/$relative_script" >/dev/null
grep -Fxq 'del network.globals.ula_prefix' "$uci_log"
grep -Fxq 'set network.globals.packet_steering=0' "$uci_log"

git -C "$workdir" apply --reverse --check "$patch_file"
echo "qualcommax preserved-network guard tests passed"
