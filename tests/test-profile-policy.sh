#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f scripts/load-profile.sh ] || { echo 'FAIL: missing profile loader'; exit 1; }
a=$(bash scripts/load-profile.sh libwrt-25.12-nss)
b=$(bash scripts/load-profile.sh immortalwrt-viking-owrt-ppe)
grep -qx 'ACCELERATION_POLICY=nss' <<< "$a"
grep -qx 'ACCELERATION_POLICY=ppe' <<< "$b"
! bash scripts/load-profile.sh ../README >/dev/null 2>&1
for policy in nss ppe upstream-native; do
  result=$(POLICY=$policy sh -c 'uci() { printf "%s\n" "$*"; }; . files/usr/lib/zn-m2/acceleration-policy.sh; zn_m2_acceleration_policy "$POLICY"')
  if [ "$policy" = upstream-native ]; then
    [ -z "$result" ]
  else
    grep -q "flow_offloading=0" <<< "$result"
    grep -q "flow_offloading_hw=0" <<< "$result"
  fi
done
! sh -c '. files/usr/lib/zn-m2/acceleration-policy.sh; zn_m2_acceleration_policy invalid' 2>/dev/null
echo 'PASS: source identity, invalid profile rejection, NSS/PPE/native policy boundaries'
