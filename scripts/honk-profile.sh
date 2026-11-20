#!/usr/bin/env bash
# Stage and validate the common Honk additions for a resolved ZN-M2 profile.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
command=${1:?usage: honk-profile.sh prepare|config|kernel TREE, or provenance}
package="$root/package/honk"
fragment="$root/configs/honk-ebpf.config"

fail() {
  printf 'Honk build: %s\n' "$*" >&2
  exit 1
}

require_line() {
  grep -Fxq "$2" "$1" || fail "$1 is missing $2"
}

case "$command" in
  prepare)
    tree=${2:?missing OpenWrt tree}
    [ -s "$tree/.config" ] || fail 'missing base configuration'
    [ ! -e "$tree/package/honk" ] || fail 'Honk package path already exists'
    cp -a "$package" "$tree/package/honk"
    # Kconfig assignments and their commented-out forms share the same key.
    awk '
      function key(line) {
        sub(/^# /, "", line)
        sub(/(=.*| is not set)$/, "", line)
        return line ~ /^CONFIG_[[:alnum:]_.+-]+$/ ? line : ""
      }
      NR == FNR { if (key($0) != "") override[key($0)] = 1; next }
      !(key($0) in override)
    ' "$fragment" "$tree/.config" > "$tree/.config.honk"
    cat "$fragment" >> "$tree/.config.honk"
    mv "$tree/.config.honk" "$tree/.config"
    ;;
  config)
    config=${2:?missing OpenWrt tree}/.config
    for symbol in DEBUG_INFO DEBUG_INFO_BTF CGROUPS CGROUP_BPF; do
      require_line "$config" "CONFIG_KERNEL_${symbol}=y"
    done
    require_line "$config" '# CONFIG_KERNEL_DEBUG_INFO_REDUCED is not set'
    require_line "$config" 'CONFIG_PACKAGE_honk=y'
    require_line "$config" 'CONFIG_PACKAGE_luci-theme-aurora=y'
    if grep -Eq '^CONFIG_PACKAGE_(luci-(app|i18n)-homeproxy[^=]*|sing-box[^=]*)=[ym]$' "$config"; then
      fail 'resolved configuration still selects a HomeProxy or sing-box package'
    fi
    ;;
  kernel)
    tree=${2:?missing OpenWrt tree}
    shopt -s nullglob
    count=0
    for image in "$tree"/build_dir/target-*/linux-qualcommax_ipq60xx/linux-*/vmlinux; do
      config="${image%/*}/.config"
      for symbol in BPF BPF_SYSCALL BPF_JIT CGROUPS CGROUP_BPF DEBUG_INFO_BTF NET_SCHED NET_CLS_ACT NET_XGRESS NET_NS; do
        require_line "$config" "CONFIG_${symbol}=y"
      done
      readelf -SW "$image" | grep -E '[[:space:]]\.BTF[[:space:]]+PROGBITS' >/dev/null ||
        fail "$image has no BTF section"
      count=$((count + 1))
    done
    [ "$count" -eq 1 ] || fail "expected exactly one compiled ZN-M2 kernel, found $count"
    ;;
  provenance)
    printf 'Honk: %s\nDoona: %s\nHonk asset SHA256: %s\n' \
      "$(sed -n 's/^HONK_ASSET_VERSION:=//p' "$package/Makefile")" \
      "$(sed -n 's/^DOONA_ASSET_VERSION:=//p' "$package/Makefile")" \
      "$(sed -n 's/^PKG_HASH:=//p' "$package/Makefile")"
    printf 'Honk config fragment SHA256: %s\n' "$(sha256sum "$fragment" | awk '{print $1}')"
    ;;
  *)
    fail "unknown command $command"
    ;;
esac
