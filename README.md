<div align="center">

# ZN-M2 有线固件

兆能 M2（ZN-M2）256M 原厂硬件的纯有线路由器固件 · 五条独立构建线 · 统一板级优化

[![LiBwrt 6.12 NSS](https://img.shields.io/github/actions/workflow/status/osGex0o0II/ZN-M2-LiBwrt-Builder/zn-m2-256m-main-router.yml?branch=main&label=6.12%20NSS&logo=github&style=flat-square)](https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/actions/workflows/zn-m2-256m-main-router.yml)
[![ImmortalWrt 6.18 PPE](https://img.shields.io/github/actions/workflow/status/osGex0o0II/ZN-M2-LiBwrt-Builder/zn-m2-256m-6.18.yml?branch=main&label=6.18%20PPE&logo=github&style=flat-square)](https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/actions/workflows/zn-m2-256m-6.18.yml)
[![ImmortalWrt 6.18 NSS](https://img.shields.io/github/actions/workflow/status/osGex0o0II/ZN-M2-LiBwrt-Builder/zn-m2-256m-viking-nss.yml?branch=main&label=6.18%20NSS&logo=github&style=flat-square)](https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/actions/workflows/zn-m2-256m-viking-nss.yml)
[![LEDE 6.12 NSS](https://img.shields.io/github/actions/workflow/status/osGex0o0II/ZN-M2-LiBwrt-Builder/zn-m2-256m-lede-nss.yml?branch=main&label=LEDE%206.12&logo=github&style=flat-square)](https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/actions/workflows/zn-m2-256m-lede-nss.yml)
[![FanchmWrt 6.12 FWX](https://img.shields.io/github/actions/workflow/status/osGex0o0II/ZN-M2-LiBwrt-Builder/zn-m2-256m-fanchmwrt-fwx.yml?branch=main&label=Fanch%206.12&logo=github&style=flat-square)](https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/actions/workflows/zn-m2-256m-fanchmwrt-fwx.yml)
[![License](https://img.shields.io/github/license/osGex0o0II/ZN-M2-LiBwrt-Builder?style=flat-square)](LICENSE)

[下载固件](../../releases) · [文档索引](docs/README.md) · [维护者说明](docs/maintainers.md) · [多上游维护](docs/multi-upstream.md)

</div>

> [!TIP]
> **已运行 OpenWrt？** 下载 `*-sysupgrade.bin`，对照发布说明里的 SHA256 校验，然后在 LuCI「系统 → 备份/升级」上传即可。首次刷机与救砖步骤已折叠在[安装与升级](#安装与升级)中。

## 目录

- [概览](#概览)
- [版本矩阵](#版本矩阵)
- [下载与校验](#下载与校验)
- [安装与升级](#安装与升级)
- [默认设置](#默认设置)
- [性能与调优](#性能与调优)
- [常见问题](#常见问题)
- [仓库结构](#仓库结构)
- [参与构建](#参与构建)
- [致谢](#致谢)
- [许可](#许可)

## 概览

| 项目 | 说明 |
|:---|:---|
| 硬件 | ZN-M2 256M 原厂版，IPQ6018 四核 Cortex-A53，无 USB 接口 |
| 形态 | 纯有线主路由；固件不含 Wi-Fi 驱动与固件，天线是否拆除不影响使用 |
| 内存 | 256 MB 物理内存，部分作为加速栈保留区；ZRAM 压缩交换按可见内存的一半创建 |
| 管理 | `192.168.1.1`，主机名 `ZN-M2`，默认简体中文 + Aurora 主题（FanchmWrt 除外） |

三条设计取舍贯穿所有版本：

- **纯有线**：去掉无线子系统与 USB，把有限的内存和中断预算留给转发与代理。
- **低内存优先**：Q6 保留区压到 16 MiB，配合 ZRAM、连接跟踪上限与 DNS 缓存调优，避免 256 MB 设备在并发下 OOM。
- **可复现**：源码、feed 与补丁全部按 commit 固定，五条线由同一套适配器、配置和回归测试产出。

## 版本矩阵

五条构建线共享硬件适配、默认网络设置与安全策略，区别在上游源码、内核与转发加速方式。每条线有独立发布标签，镜像之间不能互相覆盖。

| 构建线 | 上游 | 内核 | 转发加速 | 定位 |
|:---|:---|:---:|:---|:---|
| **ZN-M2 LiBwrt 6.12 NSS** | LiBwrt `25.12-nss` | 6.12 | NSS + ECM | 直连转发最完整，成熟稳定 |
| **ZN-M2 ImmortalWrt 6.18 PPE** | VIKINGYFY `owrt` | 6.18 | PPE + EDMA | 新内核，可用内存最多 |
| **ZN-M2 ImmortalWrt 6.18 NSS** | VIKINGYFY `main` | 6.18 | NSS + ECM | 新内核 + NSS 硬件分载 |
| **ZN-M2 LEDE 6.12 NSS** | LEDE `master` | 6.12 | NSS + ECM | 接近上游默认行为 |
| **ZN-M2 FanchmWrt 6.12 FWX** | FanchmWrt | 6.12 | FWX + Shortcut-FE | 保留上游界面与面板 |

**怎么选**

- 只在意直连转发与 PPPoE：选 **LiBwrt 6.12 NSS**，NSS 对 NAT、PPPoE、VLAN 与桥接的接管最完整。
- 想要新内核和更多可用内存：选 **ImmortalWrt 6.18 PPE**，不加载 NSS 固件。
- 新内核也要硬件分载：选 **ImmortalWrt 6.18 NSS**，代价是可用内存少约 40 MB。
- 偏好接近上游原样：选 **LEDE 6.12 NSS** 或 **FanchmWrt 6.12 FWX**。
- **代理速度与版本无关**：HomeProxy / sing-box 的流量始终由 CPU 处理，硬件加速只作用于直连转发。

**关键差异**

- **软件集**：前四条包含 Aurora 主题与 HomeProxy；FanchmWrt 使用自家主题与 FWX 面板，不含 HomeProxy。
- **默认服务**：前四条包含 DHCP 预置与健康检查；FanchmWrt 不含，行为以该上游为准。
- **默认凭据**：LEDE 为 `root` / `password`；其余版本首次登录时设置密码。FanchmWrt 以该上游默认值为准。

## 下载与校验

在 [Releases](../../releases) 页面选择对应构建线。标签由日期与构建线组成，例如 `v2026.11.05.4.1-zn-m2-lede-6.12-nss`。

每次发布只提供两个镜像：

| 文件 | 用途 |
|:---|:---|
| `*-factory.ubi` | 首次通过 U-Boot 刷入 |
| `*-sysupgrade.bin` | 设备已运行 OpenWrt 时升级 |

发布说明包含默认地址、密码策略、插件清单、优化项与两个镜像的 SHA256。下载后请先校验：

```powershell
certutil -hashfile .\ZN-M2-*-sysupgrade.bin SHA256
```

```bash
sha256sum ZN-M2-*-sysupgrade.bin
```

## 安装与升级

### 升级（已运行 OpenWrt）

在 LuCI「系统 → 备份/升级」上传 `*-sysupgrade.bin`。LuCI 默认保留配置；需要干净安装时勾选「强制擦除」。也可以在 SSH 中执行：

```bash
# 保留配置
sysupgrade /tmp/ZN-M2-*-sysupgrade.bin

# 全新安装（不保留配置）
sysupgrade -n /tmp/ZN-M2-*-sysupgrade.bin
```

**注意**

- 同一构建线内升级可以保留配置，密码、网络与代理设置都会保留。
- 6.12 与 6.18 之间、或跨上游切换时不要保留配置，内核与加速栈不同。
- 升级过程中不要断电。

<details>
<summary><b>首次刷入（原厂固件 → 过渡固件 → U-Boot → 固件）</b> · 展开查看</summary>

全程网页操作，无需拆机。

**第一步：过渡固件**

1. 网线连接电脑与路由器 LAN 口。
2. 浏览器打开原厂后台 `192.168.2.1`，用户名 `root`，密码 `admin`。
3. 进入「高级设置 → 升级固件」，取消勾选「保留配置」，上传过渡固件（文件名含 `nand-factory`，后缀 `.ubi`）。
4. 等待 1–2 分钟重启，管理地址变为 `192.168.1.1`，密码 `password`。

**第二步：写入 U-Boot**

1. 登录过渡固件，进入「系统 → 文件传输」，上传 `ax18-mibib.bin` 与 `uboot-cmiot-ax18-mod.bin`。
2. 进入「系统 → TTYD 终端」执行：

```bash
mtd write /tmp/upload/ax18-mibib.bin /dev/mtd1
mtd write /tmp/upload/uboot-cmiot-ax18-mod.bin /dev/mtd13
reboot
```

**第三步：刷入固件**

1. 用卡针按住 RESET，待 Mesh 灯闪烁后松开。
2. 电脑设为静态地址 `192.168.1.2`，掩码 `255.255.255.0`。
3. 浏览器打开 `http://192.168.1.1`，进入 U-Boot 网页界面。
4. 选择「Update firmware」，上传 `*-factory.ubi`，等待约 3 分钟。

</details>

<details>
<summary><b>救砖与串口恢复</b> · 展开查看</summary>

| 症状 | 处理方式 |
|:---|:---|
| U-Boot 正常，系统无法启动 | 进入 U-Boot 网页重新刷入固件 |
| U-Boot 损坏 | 通过 TTL 串口重新写入 U-Boot |
| 完全无响应 | 使用编程器烧录 SPI Flash |

只要 U-Boot 未损坏，都可以通过 TFTP 恢复。刷机前建议备份原厂固件。

**TTL 串口恢复**

接线：路由器 TX → 串口 RX，路由器 RX → 串口 TX，GND 对 GND，VCC 不接。串口参数 `115200 8N1`，无流控。

上电后立即连按回车进入 U-Boot 命令行：

```bash
setenv serverip 192.168.1.100
setenv ipaddr 192.168.1.1
tftpboot ax18-mibib.bin && flash 0:MIBIB
tftpboot uboot-cmiot-ax18-mod.bin && flash 0:APPSBL
tftpboot uboot-cmiot-ax18-mod.bin && flash 0:APPSBL_1
tftpboot *-factory.ubi && flash rootfs
reset
```

</details>

## 默认设置

### 首次登录

| 项目 | 默认值 |
|:---|:---|
| 管理地址 | `192.168.1.1` |
| 用户名 | `root` |
| 密码 | 首次登录时设置（LEDE 为 `password`） |
| 主机名 | `ZN-M2` |
| 界面语言 | 简体中文 |
| 界面主题 | Aurora（FanchmWrt 为自家主题） |
| DHCP 地址池 | `192.168.1.100`–`192.168.1.249` |

- 保留配置升级会沿用原有地址与密码，管理地址不一定仍是 `192.168.1.1`。
- 固件不预置公开密码。首次进入 LuCI 后请立即设置 root 密码；设置之前 SSH 不接受空密码登录。
- WAN 口连接光猫或上级路由，LAN 口连接内网设备。

### 网络

- **DHCP 预置**：开机时先写入 LAN 的 DHCP 地址段，再启动网络服务，避免首次启动时设备拿不到地址。地址段与 LAN 网段不一致时自动放弃，不会下发错误地址。
- **DNS**：使用 WAN 下发的 DNS，缓存 8192 条，并发转发上限 300。
- **连接跟踪**：上限 16384，家用与代理场景有充足余量。

### 性能

- **拥塞控制**：BBR + fq。TCP 单 socket 缓冲区上限 2 MiB，发送队列低水位 128 KiB，`tcp_mem` 保持内核默认。
- **内存压缩**：ZRAM 使用 lzo-rle，按可见内存的一半创建，约 96 MiB；仅在页面真正换出时占用内存。
- **内核内存**：Q6 保留区压到 16 MiB，连同保留区与日志调整，合计释放约 39 MiB。
- **日志**：系统与内核日志缓冲区各 256 KiB，便于重启后排查。

### 转发加速

| 构建线 | 默认状态 |
|:---|:---|
| 6.12 NSS（LiBwrt / LEDE） | NSS 硬件转发开启，软件流量分载关闭 |
| 6.18 NSS | NSS 硬件转发开启，软件流量分载关闭 |
| 6.18 PPE | PPE / EDMA 硬件分载开启 |
| FanchmWrt | FWX / Shortcut-FE 开启 |

- **NSS 与软件流量分载不要同时开启**，两者争用同一条转发路径，可能导致丢包和性能下降。
- PPE 分载会让已卸载的连接绕过防火墙规则，按连接限速、标记与统计对这部分流量不生效；需要逐连接管控时关闭分载。
- 代理流量不经过硬件加速，始终由 CPU 处理。

### 服务

| 服务 | 默认状态 |
|:---|:---|
| HomeProxy + sing-box | 已安装，未配置节点时不产生代理流量 |
| gecoosac（集客 AC） | 已安装，服务停用 |
| UPnP / ZeroTier / 网络唤醒 | 已安装，功能关闭 |
| 定时重启 | 已安装 |
| ttyd 网页终端 | 已安装，不自启 |
| CoreMark | 首次启动自动运行，约 30 秒 |
| 健康检查 | 每 10 分钟一次 |

- **健康检查**：确认 LAN 的 DHCP 服务、默认路由、DNS 解析、代理进程与可用内存；仅在需要时重启 `dnsmasq` 或 `homeproxy`，不会整机重启。可用内存低于 40 MiB 时只记录日志。
- **CoreMark**：结果写入 `/etc/bench.log`，并显示在 LuCI 概览页的 CPU 型号旁。
- **指示灯**：电源灯常亮，WAN 与 LAN 灯随链路状态变化；无 Wi-Fi 对应指示灯。
- **端口顺序**：面板从左到右为 WAN、LAN1、LAN2、LAN3，系统内的网口命名与该顺序一致；LuCI 状态页的端口面板同样把 WAN 放在最前。
- FanchmWrt 不含 DHCP 预置、健康检查与上述默认服务，行为以该上游为准。

## 性能与调优

同机实测（室温、同一套 CoreMark，4 线程总分）：

| 指标 | ImmortalWrt 6.18 NSS | ImmortalWrt 6.18 PPE | LEDE 6.12 NSS |
|:---|:---:|:---:|:---:|
| 最高频率 | 1.512 GHz | — | 1.2 GHz |
| CoreMark 4T | 19,278（首启 20,477） | — | 15,928（重跑 16,035） |
| 空载可用内存 | 62–68 MB | 105 MB | 85 MB |
| 跑分温度 | 37.5 °C | — | 37.9 °C |

- LEDE 分数较低是因为它的 CPU OPP 在这台机器上只暴露到 1.2 GHz；1512 / 1200 = 1.26，15.9k × 1.26 ≈ 20k，与 6.18 首启的 20,477 基本一致。
- 6.18 PPE 在 4 路并发 WAN 下载、约 300 Mbps 时 CPU 占用约 0.1%，连续运行 31 小时无 OOM / panic。
- 6.18 PPE 的 500 并发 LAN 下载全部成功，16 线程满载时最高 49.4 °C，无 SSH 掉线。

<details>
<summary><b>为什么 6.18 NSS 的内存占用更高</b> · 展开查看</summary>

与同内核的 6.18 PPE 空载对比，差额全部落在内核侧：

| 项目 | 6.18 NSS | 6.18 PPE | 差异 |
|:---|:---:|:---:|:---:|
| MemTotal | 199,008 kB | 214,520 kB | −15.5 MB |
| 内核预留 | 64,096 kB | 48,584 kB | +15.5 MB |
| 不可回收 Slab | 42.7 MB | 21.7 MB | +21 MB |
| VmallocUsed | 12.2 MB | 6.5 MB | +5.7 MB |
| 匿名页 | 4.5 MB | 4.5 MB | 相同 |

- **16 MB** 是 NSS 专属预留：设备树 `nss@40000000` 占 `0x40000000–0x40ffffff`，载入 NSS 固件并保留 DDR 堆，这部分不进入 MemTotal。
- **约 21 MB** 是 NSS 驱动在 Linux 侧分配的固定缓冲与连接表（EDMA RX fill 队列、host 队列、ECM 与 NSS 的连接同步表）。
- **约 5.7 MB** 是 NSS / SSDK 模块代码与映射。

4 路并发下载后多出的 1.8 MB slab 与 8.8 MB 匿名页在停止 45 秒后完全回收，多轮采样漂移小于 1 MB，无 OOM / panic / watchdog 复位。这是 NSS 硬件分载的固定成本，不是泄漏。

</details>

<details>
<summary><b>还能怎么省内存</b> · 展开查看</summary>

- 卸掉不用的隧道模块（PPTP / L2TP / GRE / MAP-T / VXLAN / TUN6RD），可省 2–4 MB，代价是失去对应分载。
- 调低 `max_ipv4_conn` / `max_ipv6_conn`（默认 4096）；这部分位于 NSS 预留堆，对 Linux 可用内存帮助有限。
- 需要更多可用内存时直接选 6.18 PPE，比 6.18 NSS 多约 40 MB，代价是没有 NSS 硬件分载。

</details>

## 常见问题

**升级后地址变了或无法上网**

跨内核升级保留了旧配置时会出现。重新刷入并在升级时取消「保留配置」，或登录后检查 LAN 地址与 WAN 协议。

**6.12 和 6.18 怎么选**

只关心直连转发选 6.12 NSS；希望使用较新内核、更多可用内存选 6.18 PPE；两者都要选 6.18 NSS。代理速度三者相同。

**内存显示只有 194–210 MiB**

硬件为 256M 版本，部分内存被 NSS/PPE 保留区与系统占用；换出的页面会压缩存入 ZRAM，不额外占用物理内存。

**支持 USB 吗**

不支持。此版本硬件无 USB 接口，固件也不包含 USB 驱动与存储工具。

**NSS 和流量分载能同时开吗**

不能。两者争用转发路径，同时开启可能导致丢包。NSS 版本默认已关闭软件分载。

**开了代理为什么没有变快**

硬件加速只处理直连转发，代理流量由 CPU 处理，速度取决于节点与 CPU。

**面板灯只亮电源灯**

刷入其他上游后可能出现灯名不一致。固件会在首次启动时按实际设备名纠正一次；若仍不亮，检查「系统 → LED 配置」中的设备名。LEDE 与 FanchmWrt 过去只绑定了电源灯，现在已补上 WAN / LAN 指示灯。

**网口和面板丝印对不上**

面板从左到右是 WAN、LAN1、LAN2、LAN3。早期 LEDE 与 FanchmWrt 镜像里 LAN1 和 LAN3 是反的（插 LAN1 却显示 lan3），现已按面板顺序修正；LiBwrt 与 ImmortalWrt 一直是正确的。升级后若仍看到旧的对应关系，请在「网络 → 接口」里确认设备名，必要时重新刷入而不保留配置。

**为什么升级后少了一些配置项**

固件会清理已不存在的软件包留下的配置，以及旧代理组件写入的 DNS 片段，避免影响现有网络。已安装软件包的配置不会被删除。

## 仓库结构

```text
.
├── .github/workflows/          # 五条构建线、依赖更新、缓存清理与发布
├── adapters/                   # 各上游的构建适配脚本
├── configs/                    # 每条构建线的软件包与内核选项
├── deps/                       # 上游源码与 feed 的版本固定
├── docs/                       # 文档索引、维护者说明、多上游说明与历史记录
├── files/                      # 通用定制文件
├── files-shared/               # 跨上游共享的配置清理与命名归一化
├── files-zn-m2/                # 256M 板级覆盖层，优先级高于 files/
├── files-upstream-native/      # 上游原生软件栈的默认项
├── patches/                    # 内核、驱动与软件包补丁
├── profiles/                   # 每条线的源码、分支、配置与适配器定义
├── scripts/                    # 构建准备、产物校验与发布说明生成
├── tests/                      # 回归测试，构建前必须全部通过
├── libwrt-6.12.sh              # 6.12 线编译定制
├── immortalwrt-6.18.sh         # 6.18 线编译定制
├── NOTICE.md                   # 第三方组件声明
└── LICENSE                     # MIT
```

三个层次各司其职：

- **profiles/** 决定一条线用哪个上游、哪个分支、哪份配置与适配器；`deps/` 固定源码与 feed 的 commit。
- **adapters/ + configs/ + patches/** 负责把上游裁剪成 256M 纯有线形态，并补齐 NSS / PPE 所需补丁。
- **files 系列目录** 是最终写进固件的运行时配置与脚本，`files-zn-m2` 覆盖 `files`，`files-shared` 处理跨上游差异。

更多细节见 [维护者说明](docs/maintainers.md) 与 [多上游维护](docs/multi-upstream.md)。

## 参与构建

- 构建由 GitHub Actions 完成，五条线各有独立 workflow；手动运行时可勾选 `publish` 发布 Release。
- 本地验证先跑 `tests/` 下的回归脚本，清单见 [tests/README.md](tests/README.md)。
- 依赖更新由定时任务发起 PR，校验通过后自动合并；版本固定值在 `deps/`。
- 发布产物只有 `factory.ubi` 与 `sysupgrade.bin`，校验值与说明由 `scripts/release-notes.sh` 生成。

## 致谢

**上游固件**

- [LiBwrt](https://github.com/LiBwrt/LibWrt) — 6.12 NSS 基础源码与 NSS 集成
- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) — 软件包与 HomeProxy 生态
- [VIKINGYFY](https://github.com/VIKINGYFY/immortalwrt) — 6.18 PPE / NSS 上游
- [LEDE](https://github.com/coolsnowwolf/lede) — 6.12 NSS 上游
- [FanchmWrt](https://github.com/fanchmwrt/fanchmwrt) — FWX 上游

**加速与驱动**

- [qosmio/nss-packages](https://github.com/qosmio/nss-packages) — NSS 驱动、ECM 与固件打包
- Qualcomm QSDK — NSS 固件与 SSDK
- OpenWrt — PPE / EDMA 分载实现

**组件与工具**

- [HomeProxy](https://github.com/immortalwrt/homeproxy) · [sing-box](https://github.com/SagerNet/sing-box) — 代理
- [Aurora](https://github.com/eamonxg/luci-theme-aurora) — LuCI 主题
- gecoosac — 集客 AC 管理
- [EEMBC CoreMark](https://www.eembc.org/coremark/) — CPU 基准测试
- GitHub Actions — 构建与发布基础设施

以及所有提交 issue、反馈实测数据和使用体验的用户。

## 许可

本项目采用 MIT 许可证，见 [LICENSE](LICENSE)。固件包含的第三方组件遵循各自许可证，详见 [NOTICE.md](NOTICE.md)。
