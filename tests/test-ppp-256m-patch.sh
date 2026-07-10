#!/bin/sh
set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
source_root="${1:-${OPENWRT_SOURCE_DIR:-}}"
patch_file="$repo_root/patches/ppp/256m-pppoe-only.patch"
makefile_path="package/network/services/ppp/Makefile"
script_path="package/network/services/ppp/files/ppp.sh"

if [ -z "$source_root" ] || [ ! -f "$source_root/$makefile_path" ] ||
   [ ! -f "$source_root/$script_path" ]; then
	echo "usage: $0 /path/to/openwrt" >&2
	exit 2
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT HUP INT TERM
mkdir -p "$workdir/$(dirname "$makefile_path")" "$workdir/$(dirname "$script_path")"
cp "$source_root/$makefile_path" "$workdir/$makefile_path"
cp "$source_root/$script_path" "$workdir/$script_path"
git -C "$workdir" init -q
git -C "$workdir" apply --check "$patch_file"
git -C "$workdir" apply "$patch_file"

makefile="$workdir/$makefile_path"
ppp_script="$workdir/$script_path"
grep -Fq 'DEPENDS:= +USE_GLIBC:libcrypt-compat +kmod-ppp' "$makefile"
if grep -Eq '(^|[[:space:]])(shellsync|kmod-mppe)([[:space:]]|$)' "$makefile"; then
	echo "256M PPP package still pulls syncdial or MPPE dependencies" >&2
	exit 1
fi
if grep -Eq 'syncdial|syncppp|shellsync' "$ppp_script"; then
	echo "256M PPPoE handler still contains syncdial support" >&2
	exit 1
fi
grep -Fq 'plugin pppoe.so' "$ppp_script"

git -C "$workdir" apply --reverse --check "$patch_file"
echo "256M PPPoE-only patch regression test passed"
