# ZN-M2 LiBwrt 6.12 NSS Builds

[中文] 本仓库使用 GitHub Actions 自动编译适用于 **ZN-M2（兆能 M2）** 路由器的 LiBwrt 固件，基于 `openwrt-6.x` 的 `main-nss` 分支，启用 Qualcomm NSS 硬件加速。

[EN] This repository builds wired-only LiBwrt `openwrt-6.x` `main-nss` firmware for ZN-M2 using GitHub Actions, with Qualcomm NSS hardware acceleration enabled.

## Variants / 固件变体

### 1G HomeProxy

- **Config / 配置**: `configs/zn-m2-1g-homeproxy.config`
- **Release tag / 发布标签**: `ZN-M2-1G-6.12-NSS-HomeProxy`
- [中文] 适用于 **1GB 内存** 升级版 ZN-M2，集成 HomeProxy + sing-box 透明代理、ttyd 网页终端。
- [EN] For the **1GB RAM** upgraded ZN-M2, includes HomeProxy, sing-box transparent proxy, and ttyd web terminal.

### 128M Performance

- **Config / 配置**: `configs/zn-m2-128m-performance.config`
- **Release tag / 发布标签**: `ZN-M2-128M-6.12-NSS-Performance`
- [中文] 适用于 **128MB 原厂内存** ZN-M2，移除代理和终端以节省空间，保留 Aurora 主题和性能调优。
- [EN] For the **128MB RAM** original ZN-M2, removes proxy and web terminal packages to save space, keeps Aurora theme and performance tuning.

## Common Features / 共同特性

- [中文] Qualcomm NSS 硬件加速（`main-nss` 分支）
- [EN] Qualcomm NSS acceleration via the `main-nss` branch
- [中文] Aurora 主题、简体中文 LuCI、主机名 `ZN-M2`
- [EN] Aurora theme, Simplified Chinese LuCI, hostname `ZN-M2`
- [中文] BBR 拥塞控制与基础网络调优
- [EN] BBR congestion control and basic network tuning
- [中文] 禁用 WiFi 和存储相关软件包（纯有线路由）
- [EN] WiFi and storage-related packages disabled (wired-only router)

## Build / 构建

[中文] 打开 GitHub Actions，运行对应变体的 workflow，构建完成后从匹配的 release tag 下载固件。

[EN] Open GitHub Actions, run the workflow for the variant you need, and download firmware from the matching release tag after the build completes.

## Default Login / 默认登录

- **Address / 地址**: `192.168.1.1`
- **User / 用户**: `root`
- **Password / 密码**: `password`
