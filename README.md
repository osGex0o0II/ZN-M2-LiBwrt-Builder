<div align="center">

# ZN-M2 LiBwrt NSS Builds

**为 ZN-M2（兆能 M2）路由器编译的 Qualcomm NSS 硬件加速固件**

[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/osGex0o0II/ZN-M2-LiBwrt-Builder/zn-m2-1g-proxy-gateway.yml?branch=main&label=1G%20Build&logo=github&style=for-the-badge)](https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/actions/workflows/zn-m2-1g-proxy-gateway.yml)
[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/osGex0o0II/ZN-M2-LiBwrt-Builder/zn-m2-256m-main-router.yml?branch=main&label=256M%20Build&logo=github&style=for-the-badge)](https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/actions/workflows/zn-m2-256m-main-router.yml)
[![OpenWrt](https://img.shields.io/badge/OpenWrt-6.x-00B5E2?logo=openwrt&logoColor=white&style=for-the-badge)](https://openwrt.org)
[![License](https://img.shields.io/github/license/osGex0o0II/ZN-M2-LiBwrt-Builder?style=for-the-badge)](LICENSE)

</div>

---

本仓库通过 GitHub Actions 自动编译 ZN-M2 路由器固件，基于 LiBwrt `openwrt-6.x` 的 `main-nss` 分支，启用 Qualcomm NSS 硬件加速。内核版本由上游源码自动检测（支持 6.12、6.18 等）。

> **硬件说明**：两个变体的 Wi-Fi 天线均已拆除，作为纯有线路由器使用。1G 改版板载 USB 3.0 数据接口已启用，256M 原厂无 USB 接口。

---

## 目录

- [硬件修改说明](#硬件修改说明)
- [固件变体](#固件变体)
- [刷机方法](#刷机方法)
- [使用指南](#使用指南)
- [默认配置](#默认配置)
- [项目结构](#项目结构)
- [性能优化](#性能优化)
- [自定义编译](#自定义编译)
- [常见问题](#常见问题)
- [致谢](#致谢)

---

## 硬件修改说明

### 天线拆除

本固件适用于已拆除 Wi-Fi 天线的 ZN-M2 路由器。天线拆除步骤如下：

1. **拆机**：拧下底部四颗螺丝，撬开外壳
2. **拆除天线**：IPX 接口天线（2.4G + 5G 共 4 根或 6 根，取决于版本），直接拔下即可
3. **难度**：⭐ 简单（仅需螺丝刀），5-10 分钟
4. **风险**：保修失效（拆机即丧失保修），硬件损坏风险极低
5. **回退**：保留天线不拆也可使用本固件，Wi-Fi 模块已在编译时完全移除（`kmod-ath11k` 等均设为 `=n`），不会发射信号

### USB 3.0 接口（仅限 1G 改版）

1G 改版板载 USB 3.0 接口已在固件中启用，支持常见 USB 存储设备、UASP、自动挂载服务，以及 ext4、exFAT、vFAT、NTFS3 等常用文件系统。256M 原厂版本无物理 USB 接口，构建时仍会禁用 USB 控制器与 PHY。

---

## 固件变体

两个变体均作为主路由使用，区别在于 1G 版额外包含透明代理能力（HomeProxy + sing-box）。

| 特性 | 1G (Mod) | 256M (Stock) |
|:---|:---:|:---:|
| 内存 | 1GB | 256MB（实际可用 ~157MB） |
| USB 3.0 | ✅（数据 + 供电） | — |
| 透明代理 (HomeProxy + sing-box) | ✅ | — |
| UPnP / Zerotier / WOL | ✅ | ✅ |
| 定时重启 | ✅ | ✅ |
| ttyd 网页终端 | ✅ | ✅ |
| 轻量健康检查 | ✅ | ✅ |
| NSS 硬件加速 | ✅ | ✅ |
| BBR 拥塞控制 | ✅ | ✅ |
| ZRAM 内存交换 | ✅ | ✅ |
| CoreMark CPU 基准测试 | ✅ | ✅ |
| Aurora 主题 | ✅ | ✅ |
| 配置文件 | [`zn-m2-1g-proxygateway.config`](configs/zn-m2-1g-proxygateway.config) | [`zn-m2-256m-mainrouter.config`](configs/zn-m2-256m-mainrouter.config) |

---

## 刷机方法

**推荐路径**：原厂固件用户使用下方「系统升级方式」，全程网页操作，无需拆机或串口线。

### 准备工作

| 项目 | 说明 |
|:---|:---|
| 必需 | 网线、电脑 |
| 固件文件 | 过渡固件（`.ubi`）、暗云 U-Boot、目标固件 |
| 可选 | USB 转 TTL 串口线（仅救砖用） |

---

### 方式一：系统升级（推荐）

适用场景：原厂固件首次刷入 OpenWrt。

#### 第一步：刷入过渡固件

1. 下载过渡固件（文件名含 `nand-factory`，格式 `.ubi`）
2. 网线连接电脑与路由器 LAN 口
3. 浏览器访问原厂后台（默认地址 `192.168.2.1`，用户名 `root`，密码 `admin`）
4. 进入「高级设置 → 升级固件」
5. 取消勾选「保留配置」，上传过渡固件
6. 等待重启完成（约 1-2 分钟）

> 重启后管理地址变为 `192.168.1.1`，默认密码 `password`。

#### 第二步：刷入 U-Boot

1. 登录过渡固件 OpenWrt 后台
2. 进入「系统 → 文件传输」，上传以下文件：
   - `ax18-mibib.bin`（分区扩容）
   - `uboot-cmiot-ax18-mod.bin`（合并分区 U-Boot）
3. 进入「系统 → TTYD 终端」，执行：

```bash
mtd write /tmp/upload/ax18-mibib.bin /dev/mtd1
mtd write /tmp/upload/uboot-cmiot-ax18-mod.bin /dev/mtd13
reboot
```

#### 第三步：刷入最终固件

1. 卡针按住 RESET 键，待 Mesh 灯闪烁完毕后松开
2. 电脑设置静态 IP `192.168.1.2`，子网 `255.255.255.0`
3. 浏览器访问 `http://192.168.1.1`（暗云 U-Boot 网页界面）
4. 点击「Update firmware」，上传最终固件（`*-factory.ubi`）
5. 等待 3 分钟，重启完成

---

### 方式二：升级（已运行 OpenWrt/LiBwrt）

1. 下载对应变体的 `*-sysupgrade.bin` 文件
2. 通过 LuCI 网页界面（系统 → 备份/升级）上传刷入，取消勾选「保留配置」
3. 或通过 SSH 执行：

```bash
sysupgrade -n /tmp/LiBwrt-*-sysupgrade.bin
```

> 建议升级时不保留旧配置（`-n`），避免跨版本配置兼容性问题。

---

<details>
<summary><b>TTL 串口方式（救砖 / 进阶）</b></summary>

适用场景：U-Boot 损坏、升级失败、需要完整备份原厂固件。

**硬件接线**

| 路由器 | 串口线 |
|:---|:---|
| TX | → RX |
| RX | → TX |
| GND | → GND |
| VCC | 不接 |

串口参数：波特率 `115200`，8N1，无流控。

**进入 U-Boot 命令行**

串口接好后上电，立即狂按回车键进入命令行。

```bash
setenv serverip 192.168.1.100
setenv ipaddr 192.168.1.1
```

**刷入 U-Boot（合并分区版）**

```bash
tftpboot ax18-mibib.bin && flash 0:MIBIB
tftpboot uboot-cmiot-ax18-mod.bin && flash 0:APPSBL
tftpboot uboot-cmiot-ax18-mod.bin && flash 0:APPSBL_1
```

**刷入固件**

```bash
tftpboot openwrt-qualcommax-ipq60xx-zn_m2-squashfs-factory.ubi && flash rootfs
reset
```

</details>

---

<details>
<summary><b>救砖指南</b></summary>

| 症状 | 解决方案 |
|:---|:---|
| U-Boot 存活，无法启动 | TTL 重新刷入固件 |
| U-Boot 网页可访问 | 直接通过网页刷入 |
| U-Boot 损坏 | TTL 刷入 U-Boot，再刷固件 |
| 完全无响应 | CH341A 编程器烧录 SPI Flash |

核心原则：只要 U-Boot 未损坏，即可通过 TFTP 恢复。刷机前建议备份原厂固件。

</details>

---

<details>
<summary><b>刷回官方固件</b></summary>

> 此操作未验证，谨慎执行。

通过 TTL 连接，使用 TFTP 刷回原厂备份：

```bash
tftpboot MIBIB.bin && flash 0:MIBIB
tftpboot APPSBL.bin && flash 0:APPSBL
tftpboot APPSBL.bin && flash 0:APPSBL_1
tftpboot rootfs.bin && flash rootfs
```

</details>

---

### 参考资源

| 资源 | 链接 |
|:---|:---|
| 恩山论坛 - 刷机指北 | [right.com.cn](https://www.right.com.cn/forum/thread-8295985-1-1.html) |
| 恩山论坛 - 固件分享 | [right.com.cn](https://www.right.com.cn/forum/thread-8262012-1-1.html) |
| B 站 - 玩数码的阿三 | [BV1RQ4y1p7gE](https://www.bilibili.com/video/BV1RQ4y1p7gE/) |
| B 站 - 你逗你玩 | [BV1Hr4y1B7F2](https://www.bilibili.com/video/BV1Hr4y1B7F2/) |
| 爱拼安小匠 - 编译教程 | [anclark.github.io](https://anclark.github.io/2023/05/28/OpenWRT/OpenWRT_ZN-M2/) |

---

## 使用指南

1. **Fork** 本仓库到你的 GitHub 账户
2. 进入 **Actions** 页面，启用 Workflows
3. 选择对应的变体 Workflow，点击 **Run workflow** 启动编译
4. 编译完成后，从 [Releases](../../releases) 页面下载固件

> 首次编译约需 2-3 小时，启用缓存后后续编译可缩短至 1 小时左右。

---

## 默认配置

| 项目 | 值 |
|:---|:---|
| 管理地址 | `192.168.1.1` |
| 用户名 | `root` |
| 密码 | `password` |
| 主机名 | `ZN-M2` |
| LuCI 语言 | 简体中文 |
| 默认主题 | Aurora |

> ⚠️ 首次登录后请立即修改默认密码。

---

## 项目结构

```
.
├── .github/workflows/           # GitHub Actions 工作流
│   ├── zn-m2-1g-proxy-gateway.yml      # 1G 版编译工作流
│   └── zn-m2-256m-main-router.yml      # 256M 版编译工作流
├── configs/                     # OpenWrt 编译配置
│   ├── zn-m2-1g-proxygateway.config    # 1G 版配置（含 HomeProxy）
│   └── zn-m2-256m-mainrouter.config    # 256M 版配置
├── files/                       # 通用自定义文件（两个变体共用）
│   ├── etc/
│   │   ├── sysctl.d/
│   │   │   └── 10-bbr.conf             # BBR + fq 网络调优（4MB 缓冲区）
│   │   └── uci-defaults/
│   │       ├── 97-cpubench.sh           # CoreMark CPU 基准测试
│   │       ├── 98-network-performance.sh # DNS 缓存调优（10000 条）
│   │       └── 99-set-ui.sh             # 系统设置（语言/主题/防火墙等）
│   └── usr/sbin/
│       └── zn-m2-healthcheck            # 通用轻量健康检查
├── files-1g/                    # 1G 版专属文件（代理网关稳定性）
│   └── etc/uci-defaults/
│       └── zz-proxygateway-stability.sh # DNS/日志/ttyd/健康检查默认项
├── files-256m/                  # 256M 版专属文件（覆盖 files/ 同名文件）
│   └── etc/
│       ├── sysctl.d/
│       │   └── 10-bbr.conf             # BBR + fq 网络调优（512KB 缓冲区）
│       └── uci-defaults/
│           ├── 98-network-performance.sh # DNS 缓存调优（4096 条）
│           ├── 99-zram.sh               # ZRAM 压缩算法（lzo-rle）
│           └── zz-mainrouter-stability.sh # 256M 保守默认项和健康检查
├── libwrt.sh                    # 编译自定义脚本
├── README.md                    # 本文档
└── LICENSE                      # MIT 许可证
```

### 文件说明

| 目录/文件 | 说明 |
|:---|:---|
| `files/` | 通用自定义文件，编译时复制到所有变体的固件根目录 |
| `files-1g/` | 1G 版专属文件，用于透明代理主路由的稳定性默认配置 |
| `files-256m/` | 256M 版专属文件，通过 OpenWrt file overlay 机制覆盖 `files/` 中的同名文件，并提供低内存设备保守默认项 |
| `libwrt.sh` | 编译时执行的自定义脚本（按变体处理 USB、注入 Aurora 主题、添加 HomeProxy 等） |
| `configs/` | OpenWrt `.config` 文件，定义软件包选择和内核配置 |

---

## 性能优化

固件默认启用以下网络优化和配置：

### BBR 拥塞控制 + fq qdisc

- TCP 拥塞控制算法设为 **BBR**，Qdisc 设为 **fq**（BBR 依赖 per-flow pacing，fq_codel 不含 pacing，混用性能下降 6-10 倍）
- TCP 缓冲区：
  - **1G 版**：**4MB**（匹配千兆 BDP 带宽延迟积）
  - **256M 版**：**512KB**（OOM 安全优先，高延迟 WAN 吞吐可能受限）
- 参考 [openwrt#7733](https://github.com/openwrt/openwrt/issues/7733)

### ZRAM 内存交换

- 压缩算法：**lzo-rle**（3.7:1 压缩比，与 lzo 同速），256M 设备使用约一半物理内存做 ZRAM swap
- 等效可用内存：~63MB × 3.7 ≈ **233MB**，大幅缓解低内存设备的 OOM 风险
- 实测效果：256M 设备运行 17 小时后可用 RAM 仍有 ~37MB（无 ZRAM 时仅剩余 ~5MB）

### NSS 硬件加速

- IPQ6000 芯片内置网络子系统（NSS），接管 NAT/路由/PPPoE/隧道等数据面处理
- 已启用 NSS 驱动的 IGMP snooping（IGS）、PPPoE 卸除、LAG（链路聚合）、Qdisc 卸载等
- **⚠️ NSS 与软件 flow offloading 不兼容**：两者竞争数据包处理路径，混用会导致数据黑洞和性能下降（参考 [qosmio/openwrt-ipq#nss-warning](https://github.com/qosmio/openwrt-ipq?tab=readme-ov-file#nss-warning)）
- 固件已默认关闭 `flow_offloading` 和 `flow_offloading_hw`。如需启用请在 LuCI → 防火墙 → 流量分载中手动打开，但注意：NSS 与 flow offloading 冲突可能导致节点黑洞，**不建议在生产环境中同时启用**

### 保守默认配置和健康检查

- 1G 版定位为**有线主路由 + NSS 加速 + HomeProxy/sing-box 透明代理网关**
- 256M 版定位为**低内存有线主路由 + NSS 加速 + 基础网络服务**
- 两个版本的 DNS 入口均固定为 dnsmasq，并默认忽略 WAN 下发 DNS，避免解析路径漂移
- `ttyd` 默认安装但不自启动，避免长期暴露网页终端；需要时可手动启用
- `/usr/sbin/zn-m2-healthcheck` 检查默认路由、dnsmasq 解析、HomeProxy/sing-box 进程和可用内存
- 1G 版每 5 分钟检查一次，内存告警阈值 32MB；256M 版每 10 分钟检查一次，内存告警阈值 16MB
- 健康检查只会按需重启 `dnsmasq` 或 `homeproxy`，不会自动整机重启
- USB 3.0 提供基础存储和维护用途，不预装 Samba、下载器或媒体服务，避免代理主路由承担 NAS 负载

### CoreMark CPU 基准测试

- 固件内置 [CoreMark](https://www.eembc.org/coremark/) 基准测试，首次启动自动运行（约 30 秒）
- 测试结果（Iterations/Sec）显示在 LuCI Overview 页面的 CPU 型号旁
- 结果会缓存到 `/etc/bench.log`，避免重复运行
- IPQ6000 @ 1.0GHz 典型分数：**~18000 Score**

---

## 自定义编译

### 修改软件包

编辑对应变体的 `.config` 文件可调整软件包（参考 [OpenWrt 包列表](https://openwrt.org/packages/start)）。

### 自定义文件

- `files/` 目录下的文件会在编译时复制到**所有变体**的固件根目录
- `files-256m/` 目录下的文件**仅对 256M 变体**生效，会覆盖 `files/` 中的同名文件
- 常见用途：自定义 sysctl 参数、UCI 默认配置、启动脚本等

### 修改编译脚本

修改 [`libwrt.sh`](libwrt.sh) 可添加自定义编译步骤：

- 禁用/启用硬件节点（DTS 修改）
- 注入第三方包（如 HomeProxy）
- 添加内核配置补丁

---

## 常见问题

### Q: 编译失败怎么办？

1. 检查 GitHub Actions 日志，找到具体错误信息
2. 常见原因：上游源码变更、依赖冲突、磁盘空间不足
3. 可尝试清除缓存后重新编译

### Q: 如何添加自定义软件包？

1. Fork 本仓库
2. 编辑 `configs/` 下对应的 `.config` 文件
3. 在 GitHub Actions 中运行编译

### Q: 256M 版本内存不够用怎么办？

- ZRAM 已默认启用，等效可用内存约 233MB
- 如仍不足，可考虑：
  - 减少不必要的软件包
  - 调低 TCP 缓冲区大小（编辑 `files-256m/etc/sysctl.d/10-bbr.conf`）
  - 关闭不需要的服务

### Q: USB 功能支持哪些版本？

1G 改版固件默认启用 USB 3.0 数据功能，并包含 USB 存储、UASP、自动挂载服务和常用文件系统支持。256M 原厂版本无物理 USB 接口，构建时会保持 USB 控制器禁用。

### Q: NSS 和 flow offloading 可以同时启用吗？

**不建议**。NSS 与软件 flow offloading 竞争数据包处理路径，可能导致：
- 数据黑洞
- 性能下降
- 节点不可达

如需 flow offloading 功能，请先禁用 NSS。

---

## 致谢

- [LiBwrt/openwrt-6.x](https://github.com/LiBwrt/openwrt-6.x) — 基础源码与 NSS 支持
- [immortalwrt/homeproxy](https://github.com/immortalwrt/homeproxy) — HomeProxy 应用
- [eamonxg/luci-theme-aurora](https://github.com/eamonxg/luci-theme-aurora) — Aurora 主题
- [EEMBC CoreMark](https://www.eembc.org/coremark/) — CPU 基准测试

---

## 许可证

[MIT](LICENSE)
