#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tree=${1:?usage: test-fanch-native.sh FORK_SOURCE}
bash "$root/adapters/fanchmwrt-25.12.sh" "$tree"
bash "$tree/tests/zn-m2-port.sh"
bash "$root/scripts/load-profile.sh" fanchmwrt-25.12 | grep -Fxq SOFTWARE_POLICY=upstream-native
echo 'FanchmWrt source port and native software selection tests passed'
