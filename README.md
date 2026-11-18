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

## 项目差异

- **四条构建线，并非同一固件的重复打包。** 分别覆盖 NSS + ECM、PPE + EDMA 和 FWX / Shortcut-FE，按数据平面和软件栈选择。
- **Wi-Fi 不在镜像中。** 不编入 Wi-Fi 驱动与固件，也不以“关闭无线”模拟纯有线；USB 同样不编入。
- **软件经过选型。** 三条 Aurora 线集成 HomeProxy + sing-box，并统一 ZeroTier、WoL、UPnP、ttyd、autoreboot、gecoosac、package-manager 等常用能力。
- **交付可追溯。** 每条 Release 附带构建清单、源码提交、SHA256 与发布门禁，不发布无法对应的二进制。

## 构建线

| 构建线 | 上游 | 内核 | 数据平面 | 适合 |
|---|---|---|---|---|
| **LiBwrt 6.12 NSS** | LiBwrt 25.12 | 6.12 | NSS + ECM | 追求 NSS 转发与成熟软件栈 |
| **ImmortalWrt 6.18 PPE** | VIKINGYFY owrt | 6.18 | PPE + EDMA | 希望降低 NSS 常驻开销 |
| **ImmortalWrt 6.18 NSS** | VIKINGYFY main | 6.18 | NSS + ECM | 6.18 内核与 NSS 组合 |
| **FanchmWrt 6.12 FWX** | FanchmWrt | 6.12 | FWX / Shortcut-FE | 偏好上游原生界面与包集 |

详细差异、验证状态和选择建议见 [构建线说明](docs/build-lines.md)。

## 内置能力

| 能力 | 说明 |
|---|---|
| 管理界面 | LiBwrt / PPE / Viking NSS 使用 Aurora 与简体中文；FanchmWrt 使用上游原生界面 |
| 代理 | 前三条集成 HomeProxy + sing-box；FanchmWrt 不包含 HomeProxy，以上游包集为准 |
| 远程与运维 | ZeroTier、WoL、UPnP、ttyd、autoreboot、gecoosac、package-manager（按构建线） |
| 运行时 | ZRAM（lzo-rle）、UCI 迁移、LuCI 端口顺序、健康检查 |
| 加速 | NSS + ECM、PPE + EDMA、FWX / Shortcut-FE；仅作用于转发，代理流量仍走 CPU |

组件大多来自上游。本项目做选型、固定、集成、默认值与验证；更完整的边界见 [功能与边界](docs/features.md)。

## 下载与开始

1. 在 [构建线说明](docs/build-lines.md) 中选择一条线。
2. 从 [Releases](https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/releases) 下载 `factory.ubi` 或 `sysupgrade.bin`，并按 [安装指南](docs/installation.md) 校验 SHA256。
3. 首次刷机使用 `factory.ubi`；已在 OpenWrt 上运行时使用 `sysupgrade.bin`。

默认管理地址为 `192.168.1.1`。跨构建线升级不保留配置。

## 兼容性

- 最低要求为原厂 **256 MB** 内存的 ZN-M2；**1 GB 扩容机型已在真机验证**。其他扩容容量以设备实际识别为准。
- 仅面向纯有线配置，不提供 Wi-Fi 或 USB 功能。
- 硬件加速只作用于符合条件的转发连接；HomeProxy / sing-box 的代理流量仍需 CPU 处理。
- Release 表示构建与发布完成，不代表每条构建线的全部功能都已完成真机验收。

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
