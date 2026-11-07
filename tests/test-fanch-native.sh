#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tree=${1:?usage: test-fanch-native.sh FORK_SOURCE}
# The adapter now rewrites the board DTS, so work on a copy and leave the
# caller's checkout untouched.
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/target/linux"
cp -R "$tree/target/linux/qualcommax" "$fixture/target/linux/"
cp -R "$tree/tests" "$fixture/tests"
bash "$root/adapters/fanchmwrt-25.12.sh" "$fixture"
bash "$fixture/tests/zn-m2-port.sh"
bash "$root/scripts/load-profile.sh" fanchmwrt-25.12 | grep -Fxq SOFTWARE_POLICY=upstream-native
echo 'FanchmWrt source port and native software selection tests passed'
