#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/tree/package"

for profile in libwrt-25.12-nss immortalwrt-viking-owrt-ppe immortalwrt-viking-main-nss; do
  stable=$(bash scripts/load-profile.sh "$profile")
  honk=$(bash scripts/load-profile.sh "$profile-ebpf")
  grep -Fxq 'SOFTWARE_POLICY=aurora-homeproxy' <<< "$stable"
  grep -Fxq 'SOFTWARE_POLICY=aurora-honk' <<< "$honk"
  grep -Fxq "CACHE_NAMESPACE=$profile-ebpf" <<< "$honk"
  for field in SOURCE_REPO SOURCE_BRANCH SOURCE_PINS PROFILE_CONFIG ACCELERATION_POLICY PROFILE_ADAPTER; do
    [ "$(grep "^$field=" <<< "$stable")" = "$(grep "^$field=" <<< "$honk")" ]
  done
  notes=$(bash scripts/release-notes.sh "$profile-ebpf")
  grep -Fq 'Honk + Doona' <<< "$notes"
  grep -Fq '待真机验收' <<< "$notes"
  if grep -Fq sing-box <<< "$notes"; then
    echo 'Honk release notes describe the original proxy stack' >&2
    exit 1
  fi
done

cat > "$tmp/tree/.config" <<'CONFIG'
CONFIG_PACKAGE_sing-box=y
CONFIG_PACKAGE_luci-app-homeproxy=y
CONFIG_PACKAGE_luci-theme-aurora=y
CONFIG_KERNEL_DEBUG_INFO_REDUCED=y
# CONFIG_KERNEL_DEBUG_INFO is not set
CONFIG
bash scripts/honk-profile.sh prepare "$tmp/tree"
bash scripts/honk-profile.sh config "$tmp/tree"
cmp package/honk/Makefile "$tmp/tree/package/honk/Makefile"
[ "$(grep -c 'DEBUG_INFO_REDUCED' "$tmp/tree/.config")" -eq 1 ]
printf 'CONFIG_PACKAGE_sing-box=m\n' >> "$tmp/tree/.config"
if bash scripts/honk-profile.sh config "$tmp/tree" 2>/dev/null; then
  echo 'Honk accepted an injected sing-box module' >&2
  exit 1
fi
if bash scripts/honk-profile.sh kernel "$tmp/tree" 2>/dev/null; then
  echo 'Honk accepted a missing kernel' >&2
  exit 1
fi
kernel="$tmp/tree/build_dir/target-aarch64/linux-qualcommax_ipq60xx/linux-6.18"
mkdir -p "$kernel"
for symbol in BPF BPF_SYSCALL BPF_JIT CGROUPS CGROUP_BPF DEBUG_INFO_BTF NET_SCHED NET_CLS_ACT NET_XGRESS NET_NS; do
  printf 'CONFIG_%s=y\n' "$symbol"
done > "$kernel/.config"
printf '__attribute__((section(".BTF"))) const char fixture[] = "fixture";\n' |
  cc -x c -c -o "$kernel/vmlinux" -
bash scripts/honk-profile.sh kernel "$tmp/tree"
sed -i '/CONFIG_NET_XGRESS=y/d' "$kernel/.config"
if bash scripts/honk-profile.sh kernel "$tmp/tree" 2>/dev/null; then
  echo 'Honk accepted a kernel without TCX' >&2
  exit 1
fi

source scripts/validate-profile-output.sh
printf '%s - fixture\n' honk v2ray-geoip v2ray-geosite luci-theme-aurora firewall4 > "$tmp/manifest"
validate_profile_manifest "$tmp/manifest" ppe aurora-honk
printf '%s - fixture\n' sing-box-tiny >> "$tmp/manifest"
if validate_profile_manifest "$tmp/manifest" ppe aurora-honk 2>/dev/null; then
  echo 'Honk accepted mixed proxy packages' >&2
  exit 1
fi

package=package/honk/files
jq -e '
  .["luci-app-honk"].read.file == {"/usr/libexec/zn-m2-honk-status":["exec"]}
  and .["luci-app-honk"].write.file == {"/etc/init.d/honk":["exec"]}
' "$package/luci/acl.d/luci-app-honk.json" >/dev/null
jq -e '.["admin/services/honk"].depends.acl == ["luci-app-honk"]' \
  "$package/luci/menu.d/luci-app-honk.json" >/dev/null
sh -n "$package/honk.init" "$package/honk.status"
IPKG_INSTROOT="$tmp/rootfs" sh -eu -c '
  enable() { exit 1; }
  disable() { echo disabled; }
  . "$1"
  enable
' sh "$package/honk.init" | grep -Fxq disabled
IPKG_INSTROOT= sh -eu -c '
  enable() { echo enabled; }
  disable() { exit 1; }
  . "$1"
  enable
' sh "$package/honk.init" | grep -Fxq enabled
if sh "$package/honk.status" unexpected; then
  echo 'LuCI read-only status script accepted an argument' >&2
  exit 1
fi
grep -Fq 'nfqueue_enable: false' "$package/config.dae"
grep -Fq 'pname(dnsmasq)' "$package/config.dae"
grep -Fq 'iifname != { "lo", "br-lan" } tcp dport 9527 reject' "$package/honk.nft"
echo 'PASS: Honk profile pairs, fragment resolution, final kernel gate, package isolation and LuCI ACL'
