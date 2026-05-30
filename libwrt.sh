#!/bin/bash
# =======================================================
# 自定义 DIY 脚本 (针对 兆能 M2 纯有线主路由)
# =======================================================

echo "========== 注入第三方 Aurora 主题 =========="
git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora package/luci-theme-aurora

echo "========== 彻底剔除默认 Bootstrap 主题 =========="
# 1. 删除已安装到 package 目录的 bootstrap
rm -rf package/feeds/luci/luci-theme-bootstrap
# 2. 删除 feeds 源码目录的 bootstrap
rm -rf feeds/luci/themes/luci-theme-bootstrap
# 3. 斩断 luci 核心包对 bootstrap 的强制依赖 (防止 make defconfig 强行拉回)
sed -i 's/+luci-theme-bootstrap//g' feeds/luci/collections/luci/Makefile
sed -i 's/+luci-theme-bootstrap//g' feeds/luci/modules/luci-base/Makefile

echo "========== DIY 脚本执行完毕 =========="
