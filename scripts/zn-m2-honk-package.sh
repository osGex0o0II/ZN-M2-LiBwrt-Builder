#!/usr/bin/env bash
#
# Stage and verify the vendored honk package for an OpenWrt source tree.
#
# Usage: zn-m2-honk-package.sh stage|verify OPENWRT_PATH
#
#   stage   copy package/honk into the tree. Runs before `make defconfig`,
#           because the package directory has to exist when the build system
#           resolves CONFIG_PACKAGE_honk=y.
#   verify  assert that the resolved .config can actually satisfy honk at
#           runtime. Runs after `make defconfig`.
#
# The package installs a prebuilt upstream binary, so nothing is compiled here.
# What is checked instead is that the tree can provide the kernel features the
# binary needs, and that no legacy proxy package was selected alongside it.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MODE=${1:?usage: zn-m2-honk-package.sh stage|verify OPENWRT_PATH}
TREE=${2:?usage: zn-m2-honk-package.sh stage|verify OPENWRT_PATH}
PKG_SRC="$ROOT/package/honk"
PKG_DST="$TREE/package/honk"

fail() { echo "zn-m2-honk-package: $*" >&2; exit 1; }

[ -d "$TREE" ] || fail "source tree not found: $TREE"
for file in "$PKG_SRC/Makefile" "$PKG_SRC/files/honk.init" \
	"$PKG_SRC/files/honk.config" "$PKG_SRC/files/config.dae"; do
	[ -f "$file" ] || fail "missing package file: $file"
done

if [ "$MODE" = stage ]; then
	# The pinned release asset is aarch64 only. qualcommax/ipq60xx is the only
	# target these profiles build, so fail loudly if that ever changes.
	[ -f "$TREE/target/linux/qualcommax/Makefile" ] ||
		fail 'honk is only packaged for qualcommax/ipq60xx (aarch64)'
	[ -f "$TREE/target/linux/qualcommax/ipq60xx/target.mk" ] ||
		fail 'honk is only packaged for qualcommax/ipq60xx (aarch64)'
	rm -rf "$PKG_DST"
	mkdir -p "$(dirname "$PKG_DST")"
	cp -a "$PKG_SRC" "$PKG_DST" || fail 'cannot stage package/honk'
	echo 'honk package staged'
	exit 0
fi

[ "$MODE" = verify ] || fail "unknown mode: $MODE"
[ -f "$TREE/.config" ] || fail "resolved config not found: $TREE/.config"

# BTF and a cgroup v2 BPF hook are non-negotiable: honk reads
# /sys/kernel/btf/vmlinux and attaches a sock_ops program to the root cgroup,
# and refuses to start when either is missing.
for symbol in CONFIG_KERNEL_DEBUG_INFO CONFIG_KERNEL_DEBUG_INFO_BTF \
	CONFIG_KERNEL_CGROUPS CONFIG_KERNEL_CGROUP_BPF; do
	grep -Fxq "${symbol}=y" "$TREE/.config" ||
		fail "$symbol=y is missing from the resolved build config"
done
# BTF depends on !KERNEL_DEBUG_INFO_REDUCED; setting BTF alone is dropped
# silently, so assert the suppression explicitly.
grep -Fxq '# CONFIG_KERNEL_DEBUG_INFO_REDUCED is not set' "$TREE/.config" ||
	fail 'CONFIG_KERNEL_DEBUG_INFO_REDUCED must be disabled or BTF is dropped'

# The package DEPENDS pulls these in, but a silent dependency failure would
# only surface on the device, so assert the resolved selection.
for package in kmod-sched-core kmod-sched-bpf kmod-nft-queue \
	kmod-nfnetlink-queue kmod-veth kmod-nf-conntrack; do
	grep -Fxq "CONFIG_PACKAGE_${package}=y" "$TREE/.config" ||
		fail "required kernel module package is not selected: $package"
done

# vmlinux-btf only installs on the exact kernel release it was generated for.
# This kernel compiles its own BTF, so the package must not appear at all.
if grep -Fxq 'CONFIG_PACKAGE_vmlinux-btf=y' "$TREE/.config"; then
	fail 'vmlinux-btf must not be selected; this kernel compiles its own BTF'
fi

# A package that is present but not selected is a silent no-op, so assert the
# config asks for it and for the geo data it links against.
for package in honk v2ray-geoip v2ray-geosite; do
	grep -Fxq "CONFIG_PACKAGE_${package}=y" "$TREE/.config" ||
		fail "package is not selected: $package"
done

# The previous proxy stack must be gone, otherwise both engines fight over the
# dae0/daens interface pair and the image ships two proxies.
for package in luci-app-homeproxy sing-box sing-box-tiny; do
	if grep -Fxq "CONFIG_PACKAGE_${package}=y" "$TREE/.config"; then
		fail "legacy proxy package still selected: $package"
	fi
done

echo 'honk package staged; kernel BTF, cgroup and module selection verified'
