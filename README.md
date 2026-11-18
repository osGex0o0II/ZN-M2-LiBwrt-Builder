<p align="center">
  <img src="docs/images/brand/mark.svg" width="96" height="96" alt="ZN-M2 No WIFI">
</p>

<h1 align="center">ZN-M2 No WIFI</h1>

<p align="center">A wired-only OpenWrt firmware for ZN-M2.</p>

<p align="center">
  <a href="https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/actions/workflows/zn-m2-256m-main-router.yml"><img src="https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/actions/workflows/zn-m2-256m-main-router.yml/badge.svg?branch=main" alt="LiBwrt 6.12 NSS"></a>
  <a href="https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/actions/workflows/zn-m2-256m-6.18.yml"><img src="https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/actions/workflows/zn-m2-256m-6.18.yml/badge.svg?branch=main" alt="ImmortalWrt 6.18 PPE"></a>
  <a href="https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/actions/workflows/zn-m2-256m-viking-nss.yml"><img src="https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/actions/workflows/zn-m2-256m-viking-nss.yml/badge.svg?branch=main" alt="ImmortalWrt 6.18 NSS"></a>
  <a href="https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/actions/workflows/zn-m2-256m-fanchmwrt-fwx.yml"><img src="https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/actions/workflows/zn-m2-256m-fanchmwrt-fwx.yml/badge.svg?branch=main" alt="FanchmWrt 6.12 FWX"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2F6FED.svg" alt="License"></a>
</p>

<p align="center">
  <a href="https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/releases">下载固件</a> ·
  <a href="docs/installation.md">安装指南</a> ·
  <a href="docs/build-lines.md">构建线</a> ·
  <a href="docs/README.md">文档索引</a>
</p>

## 概览

ZN-M2 No WIFI 是面向兆能 ZN-M2 的纯有线 OpenWrt 固件。四条构建线分别基于 LiBwrt 25.12、ImmortalWrt 6.18 与 FanchmWrt 25.12，覆盖 NSS、PPE 与 FWX 三种数据平面。

## 构建线与上游

| 构建线 | 上游 | 分支 | 内核 | 数据平面 | 界面 / 代理 |
|---|---|---|---|---|---|
| **LiBwrt 6.12 NSS** | `LiBwrt/LibWrt` | `25.12-nss` | 6.12 | NSS + ECM | Aurora；HomeProxy + sing-box |
| **ImmortalWrt 6.18 PPE** | `VIKINGYFY/immortalwrt` | `owrt` | 6.18 | PPE + EDMA | Aurora；HomeProxy + sing-box |
| **ImmortalWrt 6.18 NSS** | `VIKINGYFY/immortalwrt` | `main` | 6.18 | NSS + ECM | Aurora；HomeProxy + sing-box |
| **FanchmWrt 6.12 FWX** | `osGex0o0II/FanchmWrt` | `codex/zn-m2-25.12.6` | 6.12 | FWX / Shortcut-FE | 上游原生；不含 HomeProxy |

完整提交、配置哈希与验证状态见 [构建线说明](docs/build-lines.md) 和各 Release 的构建清单。

## 默认访问

| 项目 | 默认值 |
|---|---|
| 管理地址 | `192.168.1.1` |
| 用户名 | `root` |
| 密码 | 无预设密码；首次登录 LuCI 时设置 |
| SSH | `root@192.168.1.1`，设置密码后可用 |
| DHCP | `192.168.1.100`–`192.168.1.249` |

以上适用于 LiBwrt、ImmortalWrt PPE 与 ImmortalWrt NSS。FanchmWrt 保留上游默认值，地址、密码与插件以该线 Release 说明为准。

## 主要组件

| 组件 | 版本 | 适用 | 说明 |
|---|---|---|---|
| HomeProxy | `20261117-r3` | LiBwrt / ImmortalWrt 6.18 | 未配置节点时不产生代理流量 |
| sing-box | `1.15.0_alpha13-r1` | LiBwrt / ImmortalWrt 6.18 | HomeProxy 运行时 |
| Aurora | `1.4.3-r20261104` | LiBwrt / ImmortalWrt 6.18 | 默认简体中文 |
| gecoosac | `20261016-r1` | LiBwrt / ImmortalWrt 6.18 | 已安装，服务默认停用 |
| ZeroTier / UPnP / ttyd / autoreboot / package-manager | 随构建线 | LiBwrt / ImmortalWrt 6.18 | 已安装；功能默认关闭 |

LuCI 组件版本：LiBwrt 为 `26.315.10183~8f18275`，ImmortalWrt 6.18 为 `26.321.34033~a6adca3`。FanchmWrt 不包含 HomeProxy，保留上游原生包集；插件与版本以该线 Release 的构建清单为准。

## 下载与开始

1. 在 [构建线说明](docs/build-lines.md) 中选择一条线。
2. 从 [Releases](https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/releases) 下载 `factory.ubi` 或 `sysupgrade.bin`，并按 [安装指南](docs/installation.md) 校验 SHA256。
3. 首次刷机使用 `factory.ubi`；已在 OpenWrt 上运行时使用 `sysupgrade.bin`。

跨构建线升级不保留配置。

## 兼容性

- 适用于兆能 ZN-M2；最低 256 MB 原厂内存，1 GB 扩容机型已验证。其他容量以设备实际识别为准。
- 不提供 Wi-Fi 或 USB 功能。
- 硬件加速仅作用于转发连接；代理流量由 CPU 处理。

## 文档

| 文档 | 内容 |
|---|---|
| [安装与恢复](docs/installation.md) | 镜像选择、SHA256、首次刷机、恢复 |
| [构建线说明](docs/build-lines.md) | 四条线的差异、验证状态与选择建议 |
| [功能与边界](docs/features.md) | 插件、数据平面、运行时加固、上游与项目的分工 |
| [性能与内存](docs/performance.md) | 历史转发数据、NSS / PPE 内存差异、代理边界 |
| [常见问题](docs/faq.md) | 无 Wi-Fi、内存、代理加速、升级与恢复 |
| [文档索引](docs/README.md) | 全部用户与维护者文档 |

## 来源与许可

上游源码、软件包与品牌归各自作者所有。本仓库维护构建配置、适配器、默认值、验证与发布流程，详见 [NOTICE.md](NOTICE.md)。

本项目以 MIT 许可发布，详见 [LICENSE](LICENSE)。
