#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f scripts/load-profile.sh ] || { echo 'FAIL: missing profile loader'; exit 1; }
a=$(bash scripts/load-profile.sh libwrt-25.12-nss)
b=$(bash scripts/load-profile.sh immortalwrt-viking-owrt-ppe)
grep -qx 'ACCELERATION_POLICY=nss' <<< "$a"
grep -qx 'ACCELERATION_POLICY=ppe' <<< "$b"
! bash scripts/load-profile.sh ../README >/dev/null 2>&1

policy_run() {
  POLICY=$1 SUPPORT=$2 sh -c '
    uci() { printf "%s\n" "$*"; }
    . files/usr/lib/zn-m2/acceleration-policy.sh
    zn_m2_flowtable_supported() { [ "$SUPPORT" = 1 ]; }
    zn_m2_acceleration_policy "$POLICY"
  '
}

# NSS owns forwarding acceleration; flow offload must stay off.
nss=$(policy_run nss 1)
grep -q 'flow_offloading=0' <<< "$nss"
grep -q 'flow_offloading_hw=0' <<< "$nss"

# PPE enables hardware offload only when the kernel carries the flowtable.
ppe=$(policy_run ppe 1)
grep -q 'flow_offloading=1' <<< "$ppe"
grep -q 'flow_offloading_hw=1' <<< "$ppe"
ppe_fallback=$(policy_run ppe 0)
grep -q 'flow_offloading=0' <<< "$ppe_fallback"
grep -q 'flow_offloading_hw=0' <<< "$ppe_fallback"

# A policy is not proof of capability: the guard must inspect module metadata,
# loose module files, and the live module list. Images used in the field ship
# no modules.dep at all, so a metadata-only check must not decide the outcome.
grep -q 'modules.builtin' files/usr/lib/zn-m2/acceleration-policy.sh
grep -q 'nf_flow_table' files/usr/lib/zn-m2/acceleration-policy.sh
for probe in 'modules.dep' '/proc/modules' '.ko' '/sys/module/'; do
  grep -Fq -- "$probe" files/usr/lib/zn-m2/acceleration-policy.sh
done

# Exercise the loose-.ko and live-module probes with a fake module tree.
probe_tmp="$(mktemp -d)"
trap 'rm -rf "$probe_tmp"' EXIT
supported() {
  ZN_M2_MODULES_DIR=$1 sh -c '
    . files/usr/lib/zn-m2/acceleration-policy.sh
    zn_m2_flowtable_supported
  '
}
! supported "$probe_tmp"
: > "$probe_tmp/nft_flow_offload.ko"
supported "$probe_tmp"
rm -f "$probe_tmp/nft_flow_offload.ko"
printf 'nf_flow_table 40960 2 nft_flow_offload, Live 0x0\n' > "$probe_tmp/modules.dep"
supported "$probe_tmp"

native=$(policy_run upstream-native 1)
[ -z "$native" ]
! sh -c '. files/usr/lib/zn-m2/acceleration-policy.sh; zn_m2_acceleration_policy invalid' 2>/dev/null
echo 'PASS: source identity, invalid profile rejection, NSS/PPE/native policy boundaries'
