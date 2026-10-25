<div align="center">

# ZN-M2 256M LiBwrt NSS / ImmortalWrt 6.18 Builds

**为 ZN-M2（兆能 M2）256M 原厂版编译的双内核有线主路由固件**

[![6.12 Build](https://img.shields.io/github/actions/workflow/status/osGex0o0II/ZN-M2-LiBwrt-Builder/zn-m2-256m-main-router.yml?branch=main&label=6.12%20NSS&logo=github&style=for-the-badge)](https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/actions/workflows/zn-m2-256m-main-router.yml)
[![6.18 Build](https://img.shields.io/github/actions/workflow/status/osGex0o0II/ZN-M2-LiBwrt-Builder/zn-m2-256m-6.18.yml?branch=main&label=6.18%20no%20NSS&logo=github&style=for-the-badge)](https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/actions/workflows/zn-m2-256m-6.18.yml)
[![OpenWrt](https://img.shields.io/badge/OpenWrt-6.x-00B5E2?logo=openwrt&logoColor=white&style=for-the-badge)](https://openwrt.org)
[![License](https://img.shields.io/github/license/osGex0o0II/ZN-M2-LiBwrt-Builder?style=for-the-badge)](LICENSE)

</div>

---

本仓库通过 GitHub Actions 自动编译 ZN-M2 256M 原厂版固件，提供两个独立内核变体：

| 变体 | 源码 | 内核 | 加速路径 | Release 标签后缀 |
|:---|:---|:---:|:---|:---|
| **6.12 NSS** | LiBwrt `25.12-nss` | 6.12 | Qualcomm NSS 硬件加速 | `zn-m2-256m` |
| **6.18 no NSS** | VIKINGYFY/immortalwrt `owrt` | 6.18 | `qca-ppe` + `qca-edma`（无 NSS 固件） | `zn-m2-256m-6.18` |

两个变体使用同一套 256M 硬件适配、同一个 `files-256m` 覆盖层和同一套 HomeProxy/sing-box/gecoosac 软件栈；镜像文件名和 Release 标签完全独立，不能互相覆盖。

> **硬件说明**：本固件适用于已拆除 Wi-Fi 天线的 ZN-M2 256M 原厂版（无 USB 接口），作为纯有线路由器使用。两个变体都在编译时移除 Wi-Fi/USB 驱动与固件，DTS 中对应节点为 `disabled`。

---

## 目录

- [硬件修改说明](#硬件修改说明)
- [固件型号](#固件型号)
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

---

## 固件型号

当前仅构建 **ZN-M2 256M（原厂，无 USB 接口）**，提供两个内核变体：

| 特性 | 6.12 NSS | 6.18 no NSS |
|:---|:---:|:---:|
| 源码 | LiBwrt `25.12-nss` | VIKINGYFY/immortalwrt `owrt` |
| 内核 | 6.12 | 6.18 |
| NSS / ECM 硬件加速 | ✅ | ❌ |
| 转发路径 | NSS 固件 + ECM | `qca-ppe` + `qca-edma` |
| MemTotal（真机） | 约 196MiB（200,728 kB） | 约 192MiB（196,760 kB） |
| 透明代理 (HomeProxy + sing-box) | ✅（TUN 模式，默认安装并启用；需配置节点） | ✅（同左） |
| 集客 AC 控制器 (gecoosac) | ✅（默认安装，服务停用） | ✅（同左） |
| UPnP / ZeroTier / WOL | ✅（预装，功能默认关闭） | ✅（同左） |
| 定时重启 / ttyd / 健康检查 | ✅ / ✅（默认停用） / ✅ | ✅ / ✅（默认停用） / ✅ |
| BBR / ZRAM / CoreMark / Aurora | ✅ | ✅ |
| 镜像文件名前缀 | `LiBwrt-...` | `ImmortalWrt-...-6.18-...` |
| Release 标签后缀 | `-zn-m2-256m` | `-zn-m2-256m-6.18` |
| 配置文件 | [`zn-m2-256m-mainrouter.config`](configs/zn-m2-256m-mainrouter.config) | [`zn-m2-256m-6.18.config`](configs/zn-m2-256m-6.18.config) |

**如何选择：**

- **6.12 NSS**：直连/NAT 转发由 NSS 硬件接管，适合把 ZN-M2 当纯主路由、追求最大转发吞吐，并能接受 NSS 固件栈。
- **6.18 no NSS**：较新的内核和上游 ImmortalWrt 栈，使用 `qca-ppe`/`qca-edma`，不加载 NSS 固件；适合想跟 6.18 主线、或不需要 NSS 的场景。
- **代理场景两者相同**：HomeProxy/sing-box 的 TUN 流量始终由 CPU 处理，NSS 只加速直连转发，不会加速代理。选哪个内核主要看直连吞吐和新内核特性，而不是代理速度。

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
# 6.12 NSS
sysupgrade -n /tmp/LiBwrt-*-sysupgrade.bin
# 6.18 no NSS
sysupgrade -n /tmp/ImmortalWrt-*-6.18-sysupgrade.bin
```

> 建议升级时不保留旧配置（`-n`），避免跨版本/跨内核配置兼容性问题。6.12 与 6.18 之间切换时同样建议 `-n`，两者使用不同的内核和网络加速栈。

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
3. 选择 `ZN-M2 256M Main Router`（6.12 NSS）或 `ZN-M2 256M 6.18`（6.18 no NSS），点击 **Run workflow** 启动编译
4. 编译完成后，从 [Releases](../../releases) 页面下载对应标签的固件

> 两个 workflow 也可以按每周计划自动构建并发布独立 Release；手动 `workflow_dispatch` 默认 `firmware_release=false`，只上传 artifact，不会发布。

---

## 默认配置

| 项目 | 值 |
|:---|:---|
| 管理地址 | `192.168.1.1` |
| 用户名 | `root` |
| 密码 | 首次登录时设置 |
| 主机名 | `ZN-M2` |
| LuCI 语言 | 简体中文 |
| 默认主题 | Aurora |

> 新镜像不会注入公开默认密码。首次通过 LuCI 登录后请立即设置 root 密码；设置密码前，Dropbear 不接受空密码 SSH 登录。保留配置升级不会改写已有密码。

---

## 项目结构

```
.
├── .github/
│   ├── dependabot.yml           # Actions 版本每周检查（PR 需人工合并）
│   └── workflows/
│       ├── zn-m2-256m-main-router.yml      # 6.12 NSS 编译/发布（每周五）
│       ├── zn-m2-256m-6.18.yml             # 6.18 no NSS 编译/发布（每周六）
│       ├── auto-update-pinned-deps.yml     # 每日解析两套上游 revision 并提 PR
│       ├── auto-merge-deps.yml             # 两个验证构建通过后自动合并依赖 PR
│       └── prune-caches.yml                # 清理过期缓存；区分 6.12/6.18，总量 <8GB
├── configs/                     # OpenWrt 编译配置
│   ├── zn-m2-256m-mainrouter.config    # 6.12 NSS 配置
│   └── zn-m2-256m-6.18.config          # 6.18 no NSS 配置
├── deps/
│   ├── pinned-deps.env          # 6.12 源码/feeds/主题/sing-box 固定值
│   └── linux-6.18.env           # 6.18 源码/feeds/主题/sing-box 固定值
├── files/                       # 通用自定义文件
│   ├── etc/
│   │   ├── sysctl.d/
│   │   │   └── 10-bbr.conf             # BBR + fq 网络调优（256M 覆盖层优先）
│   │   └── uci-defaults/
│   │       ├── 95-upgrade-security-migration.sh # 升级迁移：清除旧公开密码、补 IPv6 规则
│   │       ├── 97-cpubench.sh           # CoreMark CPU 基准测试
│   │       └── 99-set-ui.sh             # 系统设置（语言/主题/防火墙/日志缓冲等）
│   └── usr/sbin/
│       └── zn-m2-healthcheck            # 通用轻量健康检查
├── files-256m/                  # 256M 专属文件（覆盖 files/ 同名文件）
│   └── etc/
│       ├── sysctl.d/
│       │   ├── 10-bbr.conf             # BBR + fq（2MiB 缓冲、backlog 2000）
│       │   └── zz-conntrack.conf       # conntrack 连接数上限（16K）
│       └── uci-defaults/
│           ├── 95-upgrade-dns-migration.sh # 升级迁移：旧固定 DNS → WAN 下发
│           ├── 98-network-performance.sh # DNS 缓存调优（8192 条）
│           ├── 99-zram.sh               # ZRAM 压缩算法（lzo-rle）
│           └── zz-mainrouter-stability.sh # 256M 默认项、健康检查、代理/gecoosac 状态
├── patches/                     # 源码补丁（packages / ppp / qca-nss / qualcommax）
├── tests/                       # 回归测试（CI 每次构建全部执行）
├── docs/                        # 设计文档与实施计划
├── libwrt.sh                    # 6.12 LiBwrt 编译自定义脚本
├── libwrt-6.18.sh               # 6.18 ImmortalWrt 编译自定义脚本
├── README.md                    # 本文档
└── LICENSE                      # MIT 许可证
```

### 文件说明

| 目录/文件 | 说明 |
|:---|:---|
| `files/` | 通用自定义文件，编译时复制到固件根目录 |
| `files-256m/` | 256M 专属文件，通过 OpenWrt file overlay 机制覆盖 `files/` 中的同名文件，并提供低内存设备默认项 |
| `libwrt.sh` | 6.12 LiBwrt 编译自定义脚本（NSS、16MiB Q6、USB 禁用、Aurora、HomeProxy） |
| `libwrt-6.18.sh` | 6.18 ImmortalWrt 编译自定义脚本（无 NSS、qca-ppe/edma、16MiB Q6、默认包过滤、Aurora、HomeProxy） |
| `deps/pinned-deps.env` | 6.12 源码、feeds、Aurora、VIKINGYFY 的固定 revision |
| `deps/linux-6.18.env` | 6.18 源码、ImmortalWrt master feeds、Aurora、VIKINGYFY 的固定 revision |
| `configs/` | OpenWrt `.config` 文件，定义软件包选择和内核配置 |

---

## 性能优化

固件默认启用以下网络优化和配置（两个内核变体共用 `files-256m` 覆盖层）：

### BBR 拥塞控制 + fq qdisc

- TCP 拥塞控制算法设为 **BBR**，Qdisc 设为 **fq**（BBR 依赖 per-flow pacing，fq_codel 不含 pacing，混用性能下降 6-10 倍）
- TCP 缓冲区上限：**2MiB**（`rmem_max`/`wmem_max` 与 `tcp_rmem`/`tcp_wmem` 的第三值）
  - 默认 `tcp_adv_win_scale=1` 时，有效接收窗口约为上限的一半，即 1MiB
  - 200ms RTT 下单流理论上限约 42Mbps（旧的 512KiB 上限只有约 10Mbps）
  - 全局 `tcp_mem` 保持内核默认（本机约 9/12/18MB），聚合 TCP 内存仍被 18MB 硬顶约束，单 socket 上限提高不会无限制吃内存
- `tcp_notsent_lowat=131072`（128KiB，Cloudflare 生产值；16KiB 会限制高 BDP 发送队列）
- `netdev_max_backlog=2000`（内核默认 1000；6.18 无 NSS 时更多流量经过 CPU，突发需要更大入口队列）
- 参考 [openwrt#7733](https://github.com/openwrt/openwrt/issues/7733)

### ZRAM 内存交换

- 压缩算法：**lzo-rle**；`zram-swap` 按内核可见内存的一半创建交换设备（256M 档约 **96MiB**）
- ZRAM 只在页面真正换出时占用内存，不是预分配；空闲时 `Used` 为 0。压缩率和实际占用取决于工作负载，可通过 `service zram status` 查看
- 256M 固件禁用 WCSS Q6，并把它的 carveout 从原始大小缩小到 **16MiB**（平台稳定性要求必须保留一段内存；16MiB 已在真机验证），内核增加约 **39MiB** 可用内存
- 真机实测：6.12 NSS `MemTotal 200,728 kB`；6.18 no NSS `MemTotal 196,760 kB`（两者都保留 16MiB NSS 保留区）

### 网络加速（按变体不同）

**6.12 NSS：**

- IPQ6000 芯片内置网络子系统（NSS），接管 NAT/路由/PPPoE/隧道等数据面处理
- 已启用 NSS 驱动的 IGMP snooping（IGS）、PPPoE 卸除、LAG（链路聚合）、Qdisc 卸载等
- 256M 构建会移除无 Wi-Fi/无隧道场景不需要的 NSS 客户端与核心代码（L2TP/PPTP/GRE、NSS crypto/EIP 固件等），同时排除无外部存储路径的 ext4/f2fs 工具和开机模块；该变体仅保留普通 PPPoE，不提供同步多拨、MPPE 或 PPTP。PPPoE、bridge、VLAN、IGS、LAG 与 Qdisc 加速保持启用
- **⚠️ NSS 与软件 flow offloading 不兼容**：两者竞争数据包处理路径，混用会导致数据黑洞和性能下降（参考 [qosmio/openwrt-ipq#nss-warning](https://github.com/qosmio/openwrt-ipq?tab=readme-ov-file#nss-warning)）
- 固件已默认关闭 `flow_offloading` 和 `flow_offloading_hw`。如需启用请在 LuCI → 防火墙 → 流量分载中手动打开，但注意：NSS 与 flow offloading 冲突可能导致节点黑洞，**不建议在生产环境中同时启用**

**6.18 no NSS：**

- 不加载 NSS/ECM 驱动，也不保留 NSS 固件依赖；直连转发使用 `qca-ppe` + `qca-edma`
- 真机验证：内核 6.18.55、`lsmod` 中无 `qca_nss`/`ecm`、LAN 1Gbps 正常、720Mbps 本地吞吐、重启正常
- 代理流量仍然由 CPU 处理；没有 NSS 意味着直连大流量转发的 CPU 占用会高于 6.12 NSS 变体

### 透明代理（HomeProxy + sing-box）

- 默认安装 HomeProxy 与 sing-box（均来自 pinned `VIKINGYFY/packages`），入站为 **TUN + auto_redirect**
- 首次使用需在 LuCI → 服务 → HomeProxy 导入订阅/节点；未配置节点时服务保持空闲，不产生代理流量
- 代理流量由 CPU 处理：**NSS 只加速直连/NAT 转发，不加速 TUN/TPROXY 代理流量**；6.18 无 NSS，代理同样由 CPU 处理
- `gecoosac` 仅预装，服务默认停用（它是集客 AP 的 AC 控制器，不是代理）

### 低内存默认配置和健康检查

- 定位为**低内存有线主路由 + 基础网络服务 + 可选透明代理**
- DNS 入口为 dnsmasq，默认采用 WAN 下发 DNS；`cachesize=8192`（OpenWrt 默认 1000，dnsmasq 上限 10000），`dnsforwardmax=300`
- 系统日志环形缓冲 **256KiB**（`log_size` + `log_buffer_size`），内核 log buffer 通过 `CONFIG_LOG_BUF_SHIFT=18` 提升到 256KiB，便于重启/崩溃后排查
- conntrack 上限保持 **16384**；当前空闲约 100 条，16K 对家用/代理场景有充足余量
- `vm.min_free_kbytes=16384` 来自上游 OpenWrt 对 >128MB 设备的默认水位，不是预分配；`vm.swappiness=60`
- LuCI/uHTTPd 默认提高到 8 个并发请求，减少概览页多个状态卡片并行加载时的排队等待
- `ttyd` 默认安装但不自启动，避免长期暴露网页终端；需要时先在 LuCI → 系统 → 启动项中启动/启用 `ttyd`，再进入 LuCI → 系统 → 终端
- 预装 UPnP、ZeroTier 和网络唤醒（WOL）的 LuCI 入口。UPnP/ZeroTier 功能配置默认关闭且不产生常驻后台负载，需要时可在 LuCI 中手动启用
- `/usr/sbin/zn-m2-healthcheck` 独立检查 LAN DHCP 运行段 range/UDP 67，再检查默认路由、dnsmasq 解析、HomeProxy/sing-box 进程和可用内存；LAN 接口重新上线时会立即触发 DHCP-only 复核
- 每 10 分钟检查一次，内存告警阈值 **40MiB**（仅写日志，不会因为低内存自动重启服务）
- 健康检查只会按需重启 `dnsmasq` 或 `homeproxy`，不会自动整机重启

### CoreMark CPU 基准测试

- 两个内核变体均内置 [CoreMark](https://www.eembc.org/coremark/) 基准测试，首次启动自动运行（约 30 秒），写入真实 CPU Mark；如果二进制缺失则不会写入占位分数
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

修改 [`libwrt.sh`](libwrt.sh)（6.12 LiBwrt）或 [`libwrt-6.18.sh`](libwrt-6.18.sh)（6.18 ImmortalWrt）可添加自定义编译步骤：

- 禁用/启用硬件节点（DTS 修改）
- 添加内核配置补丁
- 过滤目标默认软件包

### 依赖自动更新

上游源码/feeds、Aurora 稳定版、以及 VIKINGYFY 包仓库提交集中记录在两套 pin 文件中：[`deps/pinned-deps.env`](deps/pinned-deps.env)（6.12 LiBwrt）和 [`deps/linux-6.18.env`](deps/linux-6.18.env)（6.18 ImmortalWrt）。HomeProxy 与 sing-box 均直接来自固定的 [VIKINGYFY/packages](https://github.com/VIKINGYFY/packages) feed（该仓库自带 sing-box 并自动跟踪上游最新版，含预发布版本），两套内核共用同一个 `VIKINGYFY_COMMIT`。`Auto-update pinned dependencies` workflow 每日检查这些 revision 和稳定版 release，更新两个文件并创建依赖 PR；该分支的推送会触发 6.12 和 6.18 两个固件 workflow 作为 PR checks 运行（`firmware_release=false`，不会发布 Release）。为让推送能够触发验证构建，仓库需配置具备 `repo` 与 `workflow` 权限的 `AUTO_UPDATE_TOKEN` secret（GitHub App installation token 或 classic PAT）。固定的 packages feed 若包含上游已知的 Kconfig 递归依赖缺陷（如 freeradius3 3.2.10 的 OpenSSL 选择环、weechat 的 minimal/full 变体互相 select 与 conflicts），`libwrt.sh` 会在构建时自动应用 `patches/packages/` 中的修复并按补丁前后状态校验结果；对上游已修复、或尚未引入该包的历史 revision 会自动跳过。6.18 master feeds 中与所选包无关的 Kconfig 递归（qt5base/squeezelite）只记录警告，最终由显式 config 断言和 manifest 门禁兜底。

验证通过后，`Auto-merge dependency updates` workflow 会自动合并安全的依赖更新 PR。合并条件被限制为 `github-actions[bot]` 或 GitHub Actions App 作者、固定更新分支、仅改动 `deps/pinned-deps.env` / `deps/linux-6.18.env` 的文件白名单，以及 head 提交上由 GitHub Actions 产生的 **6.12 与 6.18 两个**固件验证 check run 均为 `completed`/`success`。最终合并交由 GitHub auto-merge 执行，并用 `--match-head-commit` 锁定刚被校验的提交，因此即使 `pull_request` 触发的运行被审批策略拦截，依赖更新仍可自动合入。GitHub Actions 自身版本由 Dependabot 每周检查并提交更新 PR；这类 PR **不会**被自动合并，需要人工审查后手动合并。`Prune Actions caches` workflow 每天清理 PR 作用域缓存和已退役的 1G 缓存，按 6.12/6.18 变体分别保留分支缓存的最新两代；当仓库缓存总量超过 8GB 时，再按最久未使用顺序删除，避免触发 GitHub 的缓存驱逐抖动。

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

### Q: 6.12 和 6.18 怎么选？

- 追求直连/NAT 最大吞吐、需要 NSS 硬件加速 → **6.12 NSS**。
- 想跟 6.18 内核/上游 ImmortalWrt 栈、不需要 NSS 固件 → **6.18 no NSS**。
- 主要跑 HomeProxy/sing-box → 两者代理都由 CPU 处理，差距主要在直连转发；按内核偏好选即可。
- 两个变体的 Release 标签、镜像名、配置完全不重叠，可以并存；切换时建议 `sysupgrade -n`。

### Q: 256M 版本内存不够用怎么办？

- 先看 `free -m`、`logread | grep zn-m2-healthcheck` 和 `ps w` 里 sing-box/gecoosac 的实际 RSS
- ZRAM 已默认启用（约 96MiB，lzo-rle）；空闲时未使用是正常的
- TCP 缓冲区已按代理场景调到 2MiB 单 socket，但全局 `tcp_mem` 仍限制在约 18MB；不要因为一时内存紧张把 `tcp_mem` 无限抬高
- 如仍不足，优先：
  - 减少 HomeProxy 规则集/关闭不用的代理节点
  - 停用 gecoosac 等不需要的服务
  - 减少不必要的软件包
  - 用 `logread` 确认是否有进程泄漏，而不是直接缩小所有缓冲区

### Q: USB 功能支持哪些版本？

当前仅构建 **ZN-M2 256M 原厂版**，该硬件没有 USB 接口，两个内核变体都会在 DTS 和软件包层面禁用 USB 控制器、PHY 与存储栈；不再提供 1G 改版固件。

### Q: NSS 和 flow offloading 可以同时启用吗？

这个问题只适用于 **6.12 NSS** 变体。**不建议**同时启用：NSS 与软件 flow offloading 竞争数据包处理路径，可能导致：
- 数据黑洞
- 性能下降
- 节点不可达

6.18 没有 NSS，使用 `qca-ppe`/`qca-edma`，不存在这个冲突。

### Q: 6.18 为什么没有 NSS？

6.18 树（VIKINGYFY/immortalwrt `owrt`）当前没有可用的 NSS/ECM 驱动栈，因此改用上游的 `qca-ppe` + `qca-edma`。这不会影响 LAN/WAN 基本转发和代理功能，但直连大流量转发的 CPU 占用会高于 6.12 NSS 变体。

---

## 致谢

- [LiBwrt/LibWrt](https://github.com/LiBwrt/LibWrt) — 6.12 基础源码与 NSS 支持
- [VIKINGYFY/immortalwrt](https://github.com/VIKINGYFY/immortalwrt) — 6.18 源码树（`owrt`，无 NSS）
- [immortalwrt/homeproxy](https://github.com/immortalwrt/homeproxy) — HomeProxy 应用上游
- [VIKINGYFY/packages](https://github.com/VIKINGYFY/packages) — HomeProxy 应用与 sing-box 软件包（当前构建来源）
- [eamonxg/luci-theme-aurora](https://github.com/eamonxg/luci-theme-aurora) — Aurora 主题
- [EEMBC CoreMark](https://www.eembc.org/coremark/) — CPU 基准测试

---

## 许可证

[MIT](LICENSE)
