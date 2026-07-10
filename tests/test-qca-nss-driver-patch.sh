#!/bin/sh
set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
patch_file="$repo_root/patches/qca-nss-drv/profile-config-depends.patch"
feed_dir="${1:-${NSS_DRIVER_FEED_DIR:-}}"

if [ -z "$feed_dir" ] || [ ! -f "$feed_dir/Makefile" ]; then
	echo "usage: $0 /path/to/nss-packages/qca-nss-drv" >&2
	exit 2
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT HUP INT TERM
mkdir -p "$workdir/qca-nss-drv"
cp "$feed_dir/Makefile" "$workdir/qca-nss-drv/Makefile"
git -C "$workdir" init -q
git -C "$workdir" apply --check "$patch_file"
git -C "$workdir" apply "$patch_file"

config_deps="$(sed -n '/^PKG_CONFIG_DEPENDS:=/,/^$/p' "$workdir/qca-nss-drv/Makefile")"
for profile in HIGH MEDIUM LOW; do
	printf '%s\n' "$config_deps" | grep -Fq "CONFIG_NSS_MEM_PROFILE_${profile}" || {
		echo "missing NSS ${profile} profile from PKG_CONFIG_DEPENDS" >&2
		exit 1
	}
done
printf '%s\n' "$config_deps" | grep -Fq 'CONFIG_NSS_FIRMWARE_VERSION_12_5' || {
	echo "missing NSS 12.5 firmware version from PKG_CONFIG_DEPENDS" >&2
	exit 1
}

git -C "$workdir" apply --reverse --check "$patch_file"
echo "qca-nss-drv profile dependency patch tests passed"
