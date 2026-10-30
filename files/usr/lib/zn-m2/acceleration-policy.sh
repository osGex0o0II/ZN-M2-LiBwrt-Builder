#!/bin/sh
# A configured policy is not proof that acceleration is active.
#
# PPE flow offload was measured on the 6.18 no-NSS image: hardware offload
# keeps the CPU at ~0.1% during a ~300 Mbps NAT download (8.3% without it) and
# payload hashes matched with offload on and off. Enabling it is therefore the
# default for PPE, but only when the kernel actually carries the flowtable and
# nft_flow_offload objects.
zn_m2_flowtable_supported() {
  release="$(uname -r 2>/dev/null || true)"
  [ -n "$release" ] || return 1
  moddir="${ZN_M2_MODULES_DIR:-/lib/modules/$release}"
  for list in "$moddir/modules.builtin" "$moddir/modules.dep"; do
    [ -r "$list" ] || continue
    grep -qE 'nf_flow_table|nft_flow_offload' "$list" && return 0
  done
  return 1
}

zn_m2_acceleration_policy() {
  case "$1" in
    nss)
      # NSS owns the forwarding path; a competing flowtable breaks offload.
      uci -q set firewall.@defaults[0].flow_offloading=0
      uci -q set firewall.@defaults[0].flow_offloading_hw=0
      ;;
    ppe)
      if zn_m2_flowtable_supported; then
        uci -q set firewall.@defaults[0].flow_offloading=1
        uci -q set firewall.@defaults[0].flow_offloading_hw=1
      else
        uci -q set firewall.@defaults[0].flow_offloading=0
        uci -q set firewall.@defaults[0].flow_offloading_hw=0
      fi
      ;;
    upstream-native) ;;
    *) echo "Unknown acceleration policy: $1" >&2; return 1 ;;
  esac
}
