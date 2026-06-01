<div align="center">

# ZN-M2 LiBwrt 6.12 NSS Builds

**为 ZN-M2（兆能 M2）路由器编译的 Qualcomm NSS 硬件加速固件**

[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/osGex0o0II/openwrt-ci-o/ZN-M2-1G-128M-HomeProxy.yml?branch=main&label=HomeProxy%20Build&logo=github&style=for-the-badge)](https://github.com/osGex0o0II/openwrt-ci-o/actions/workflows/ZN-M2-1G-128M-HomeProxy.yml)
[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/osGex0o0II/openwrt-ci-o/ZN-M2-256M-128M-Performance.yml?branch=main&label=Performance%20Build&logo=github&style=for-the-badge)](https://github.com/osGex0o0II/openwrt-ci-o/actions/workflows/ZN-M2-256M-128M-Performance.yml)
[![OpenWrt](https://img.shields.io/badge/OpenWrt-6.12-00B5E2?logo=openwrt&logoColor=white&style=for-the-badge)](https://openwrt.org)
[![License](https://img.shields.io/github/license/osGex0o0II/openwrt-ci-o?style=for-the-badge)](LICENSE)

</div>

---

<div align="center">

![Preview](https://raw.githubusercontent.com/eamonxg/assets/master/aurora/preview/theme/multi-device-showcase.png)

</div>

---

本仓库通过 GitHub Actions 自动编译 ZN-M2 路由器固件，基于 LiBwrt `openwrt-6.x` 的 `main-nss` 分支，启用 Qualcomm NSS 硬件加速。提供两个变体以适配不同的硬件配置和使用场景。

## 固件变体

| 特性 | 1G-128M HomeProxy | 256M-128M Performance |
|:---|:---:|:---:|
| 硬件版本 | 1GB 内存改版 | 256MB 内存原厂 |
| 透明代理 (HomeProxy + sing-box) | ✅ | — |
| UPnP / Zerotier / WOL | — | ✅ |
| 定时重启 / 流量统计 | — | ✅ |
| ttyd 网页终端 | ✅ | ✅ |
| NSS 硬件加速 | ✅ | ✅ |
| Aurora 主题 | ✅ | ✅ |
| 配置文件 | [`zn-m2-1g-128m-homeproxy.config`](configs/zn-m2-1g-128m-homeproxy.config) | [`zn-m2-256m-128m-performance.config`](configs/zn-m2-256m-128m-performance.config) |

## 使用指南

1. **Fork** 本仓库到你的 GitHub 账户
2. 进入 **Actions** 页面，启用 Workflows
3. 选择对应的变体 Workflow，点击 **Run workflow** 启动编译
4. 编译完成后，从 **Releases** 页面下载固件

> 首次编译约需 2-3 小时，启用缓存后后续编译可缩短至 1 小时左右。

## 默认配置

| 项目 | 值 |
|:---|:---|
| 管理地址 | `192.168.1.1` |
| 用户名 | `root` |
| 密码 | `password` |
| 主机名 | `ZN-M2` |
| LuCI 语言 | 简体中文 |
| 默认主题 | Aurora |

## 自定义

- 编辑对应变体的 `.config` 文件可调整软件包
- `files/` 目录下的文件会在编译时复制到固件根目录
- 修改 [`libwrt.sh`](libwrt.sh) 可添加自定义编译步骤

## 致谢

- [LiBwrt/openwrt-6.x](https://github.com/LiBwrt/openwrt-6.x) — 基础源码与 NSS 支持
- [immortalwrt/homeproxy](https://github.com/immortalwrt/homeproxy) — HomeProxy 应用
- [eamonxg/luci-theme-aurora](https://github.com/eamonxg/luci-theme-aurora) — Aurora 主题

## 许可证

[MIT](LICENSE)
