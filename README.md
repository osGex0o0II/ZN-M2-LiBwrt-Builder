<div align="center">

# ZN-M2 有线固件

面向兆能 ZN-M2 原厂 256 MB 版本的多上游有线路由固件。

[![LiBwrt 6.12 NSS](https://img.shields.io/github/actions/workflow/status/osGex0o0II/ZN-M2-LiBwrt-Builder/zn-m2-256m-main-router.yml?branch=main&label=LiBwrt%206.12%20NSS&style=flat-square)](https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/actions/workflows/zn-m2-256m-main-router.yml)
[![ImmortalWrt 6.18 PPE](https://img.shields.io/github/actions/workflow/status/osGex0o0II/ZN-M2-LiBwrt-Builder/zn-m2-256m-6.18.yml?branch=main&label=ImmortalWrt%206.18%20PPE&style=flat-square)](https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/actions/workflows/zn-m2-256m-6.18.yml)
[![ImmortalWrt 6.18 NSS](https://img.shields.io/github/actions/workflow/status/osGex0o0II/ZN-M2-LiBwrt-Builder/zn-m2-256m-viking-nss.yml?branch=main&label=ImmortalWrt%206.18%20NSS&style=flat-square)](https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/actions/workflows/zn-m2-256m-viking-nss.yml)
[![FanchmWrt 6.12 FWX](https://img.shields.io/github/actions/workflow/status/osGex0o0II/ZN-M2-LiBwrt-Builder/zn-m2-256m-fanchmwrt-fwx.yml?branch=main&label=FanchmWrt%206.12%20FWX&style=flat-square)](https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/actions/workflows/zn-m2-256m-fanchmwrt-fwx.yml)
[![MIT License](https://img.shields.io/github/license/osGex0o0II/ZN-M2-LiBwrt-Builder?style=flat-square)](LICENSE)

[下载固件](../../releases) · [安装指南](docs/installation.md) · [文档索引](docs/README.md)

</div>

## 项目概述

- **适用设备**：兆能 ZN-M2 原厂 256 MB 版本，Qualcomm IPQ6018。
- **系统形态**：纯有线路由；构建时移除 Wi-Fi 相关驱动及固件，不提供 USB 功能。
- **构建方式**：通过 GitHub Actions 为四条上游构建线生成独立镜像。
- **版本追踪**：LiBwrt 与两条 ImmortalWrt 构建线在构建时解析上游提交；FanchmWrt 使用固定依赖。具体版本可依据构建记录核查。

本仓库针对 256 MB 设备进行裁剪与配置适配，但各构建线的运行时设置并不完全相同。**构建成功不等于所有功能均已通过真机验证。**

## 固件版本

| 构建线 | 上游分支 | 内核 | 转发加速 |
|:---|:---|:---:|:---|
| **LiBwrt 6.12 NSS** | LiBwrt `25.12-nss` | Linux 6.12 | NSS + ECM |
| **ImmortalWrt 6.18 PPE** | VIKINGYFY `owrt` | Linux 6.18 | PPE + EDMA |
| **ImmortalWrt 6.18 NSS** | VIKINGYFY `main` | Linux 6.18 | NSS + ECM |
| **FanchmWrt 6.12 FWX** | FanchmWrt 定制分支 | Linux 6.12 | FWX / Shortcut-FE |

### 版本选择

- **LiBwrt 6.12 NSS**：面向需要 NSS 转发路径的有线主路由。
- **ImmortalWrt 6.18 PPE**：采用 PPE 硬件分载，不加载 NSS 固件；历史测试中空载可用内存较多。
- **ImmortalWrt 6.18 NSS**：在 Linux 6.18 上使用 NSS + ECM；额外的 NSS 组件会占用内存。
- **FanchmWrt 6.12 FWX**：保留该上游的软件界面与 FWX 快速转发体系。

前两条为既有主力构建线；后两条使用独立适配流程，属于实验构建配置，虽已提供 Release，也不代表全部功能完成验收。硬件加速主要针对符合条件的转发连接；HomeProxy / sing-box 的代理流量仍需 CPU 处理，其性能不能用直连吞吐量代替。

### 软件差异

| 项目 | LiBwrt / ImmortalWrt | FanchmWrt |
|:---|:---|:---|
| 管理界面 | LuCI + Aurora | 上游原生界面 |
| 代理组件 | HomeProxy + sing-box | 以上游包集为准 |
| 运行时策略 | 项目提供部分默认值与健康检查 | 主要沿用上游设置 |
| 加速策略 | 按 NSS / PPE 构建线分别设置 | 使用上游 FWX / fastnat |

## 下载与安装

在 [Releases](../../releases) 中选择构建线，下载与设备及当前刷机环境相匹配的镜像。

| 文件 | 适用场景 |
|:---|:---|
| `*-factory.ubi` | 通过兼容的 U-Boot 环境刷入 |
| `*-sysupgrade.bin` | 从受支持的 OpenWrt 系固件升级 |

每个 Release 的说明附有对应镜像的 SHA256，刷入前必须核对。

```powershell
# Windows：替换为实际下载的文件名
certutil -hashfile "固件文件名.bin" SHA256
```

```bash
# Linux
sha256sum "固件文件名.bin"
```

**升级原则：**

1. 同一构建线升级通常可保留配置，但应先备份并核对发布说明。
2. 跨构建线、跨内核或切换加速栈时，不保留原配置；不要直接恢复其他构建线的备份。
3. 升级期间不要断电，也不要绕过固件的设备兼容性检查。
4. `*-factory.ubi` 不能直接等同于原厂固件升级包；首次刷机前须核实引导程序与分区布局。

完整步骤及恢复注意事项见 [安装与恢复](docs/installation.md)。

## 默认配置

以下为项目定制构建线的常见初始配置。保留配置升级后仍以设备当前设置为准；FanchmWrt 的凭据、主题和服务配置以上游及对应 Release 为准。

| 项目 | 初始配置 |
|:---|:---|
| 管理地址 | `192.168.1.1` |
| 管理用户 | `root` |
| 主机名 | `ZN-M2`（主力构建线） |
| DHCP 地址池 | `192.168.1.100`–`192.168.1.249`（主力构建线） |
| 管理密码 | 主力构建线首次登录后设置；其他构建线以发布说明为准 |

首次登录后应立即设置安全密码。WAN 连接光猫或上级路由，LAN 连接内网设备。

**运行时说明：**

- NSS 构建线默认关闭与之竞争的软件流量分载。
- PPE 构建线按内核支持情况配置硬件流量分载。
- ZRAM 将交换页面压缩后存储于内存中，仍会消耗物理 RAM。
- 硬件分载可能影响部分逐包 QoS、流量统计或防火墙扩展功能，需在实际网络中验证。

具体测试数据与限制见 [性能与内存测试](docs/performance.md)。

## 构建与维护

四条构建线均使用 GitHub Actions，按各自工作流构建与发布。

- LiBwrt 6.12 NSS、ImmortalWrt 6.18 PPE：手动运行时使用 `firmware_release` 选择是否发布。
- ImmortalWrt 6.18 NSS、FanchmWrt 6.12 FWX：手动运行时使用 `publish` 选择是否发布。
- 计划构建可自动发布 Release；提交触发的构建不应被视为已发布版本。
- 部分上游源代码和 feeds 在构建时跟踪分支最新提交，实际使用的 revision 应以该次构建记录为准。

构建维护说明见 [维护者文档](docs/maintainers.md)，上游适配与验收要求见 [多上游维护](docs/multi-upstream.md)。

## 常见问题

**升级后管理地址或网络设置不同？** 保留配置会沿用设备原有设置。跨构建线升级不应直接复用旧配置。

**为什么系统显示的内存少于 256 MB？** 部分内存由内核、固件和加速组件保留；ZRAM 不是额外的物理内存。

**代理能利用 NSS、PPE 或 FWX 加速吗？** 这些机制主要加速符合条件的转发连接，不能假定用户态代理流量获得同等收益。

**设备无法启动怎么办？** 先判断 U-Boot 是否可用，切勿直接尝试来源不明的分区写入命令。参见 [安装与恢复](docs/installation.md)。

## 致谢与许可

本项目基于 [LiBwrt](https://github.com/LiBwrt/LibWrt)、[ImmortalWrt](https://github.com/immortalwrt/immortalwrt)、[VIKINGYFY/immortalwrt](https://github.com/VIKINGYFY/immortalwrt)、[FanchmWrt](https://github.com/fanchmwrt/fanchmwrt) 及 OpenWrt 生态中的驱动与软件包。

本仓库自有代码以 [MIT](LICENSE) 许可发布；固件所含第三方组件仍适用各自的许可证，详见 [NOTICE.md](NOTICE.md)。
