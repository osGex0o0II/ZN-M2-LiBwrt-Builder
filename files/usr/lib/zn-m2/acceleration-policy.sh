#!/bin/sh
# A configured policy is not proof that acceleration is active.
zn_m2_acceleration_policy() {
  case "$1" in
    nss|ppe)
      # NSS avoids competing flowtables; PPE stays conservative until validated.
      uci -q set firewall.@defaults[0].flow_offloading=0
      uci -q set firewall.@defaults[0].flow_offloading_hw=0
      ;;
    upstream-native) ;;
    *) echo "Unknown acceleration policy: $1" >&2; return 1 ;;
  esac
}
