#!/usr/bin/env bash
set -euo pipefail

echo "========== Inject Aurora theme =========="
rm -rf package/luci-theme-aurora
git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora package/luci-theme-aurora

echo "========== Replace HomeProxy for sing-box 1.12 =========="
rm -rf \
  feeds/luci/applications/luci-app-homeproxy \
  package/feeds/luci/luci-app-homeproxy \
  package/luci-app-homeproxy

git clone --depth=1 https://github.com/immortalwrt/homeproxy package/luci-app-homeproxy

test -f package/luci-app-homeproxy/Makefile

echo "========== Custom package sources ready =========="
