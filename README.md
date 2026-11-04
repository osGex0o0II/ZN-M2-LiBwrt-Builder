<div align="center">

# ZN-M2 有线固件

面向 ZN-M2（兆能 M2）256M 原厂硬件的路由器固件，提供五条独立构建线。

[![License](https://img.shields.io/github/license/osGex0o0II/ZN-M2-LiBwrt-Builder?style=for-the-badge)](LICENSE)

</div>

---

## 适用范围

- **硬件**：ZN-M2 256M 原厂版，无 USB 接口。
- **用途**：纯有线主路由。固件不包含 Wi-Fi 驱动与固件，安装后不会发射无线信号；天线是否拆除不影响使用。
- **内存**：约 195 MiB 可用，其中一半用于 ZRAM 压缩交换。

## 版本选择

五条构建线的硬件适配、默认网络设置与安全策略一致，区别在于上游源码、内核和转发加速方式。每条线有独立的发布标签，镜像之间不能互相覆盖。

| 构建 | 内核 | 转发加速 | 上游 | 适合 |
|:---|:---:|:---|:---|:---|
| **ZN-M2 LiBwrt 6.12 NSS** | 6.12 | NSS + ECM | LiBwrt | 直连转发优先 |
| **ZN-M2 ImmortalWrt 6.18 PPE** | 6.18 | PPE + EDMA | ImmortalWrt | 新内核优先 |
| **ZN-M2 VIKING 6.18 NSS** | 6.18 | NSS + ECM | ImmortalWrt main | 新内核 + NSS |
| **ZN-M2 LEDE 6.12 NSS** | 6.12 | NSS + ECM | LEDE | 偏好上游默认行为 |
| **ZN-M2 FanchmWrt 6.12 FWX** | 6.12 | FWX + Shortcut-FE | FanchmWrt | 偏好上游自带界面 |

### 主要区别

- **转发加速**：NSS 由 Qualcomm NSS 硬件接管 NAT、PPPoE、VLAN 与桥接；PPE 走较新内核的 PPE/EDMA 分载；FWX 使用 Shortcut-FE 快速转发。三者都不处理代理流量。
- **内核**：6.12 系列成熟稳定，6.18 系列跟随较新上游。
- **软件集**：前四条包含 Aurora 主题与 HomeProxy；FanchmWrt 使用自家主题与 FWX 面板，不含 HomeProxy。
- **默认服务**：前四条包含 DHCP 预置与健康检查；FanchmWrt 不含，行为以该上游为准。
- **默认凭据**：LEDE 为 `root` / `password`，首次登录后请立即修改；其余版本首次登录无密码。

### 如何选择

- 只看直连转发性能：选 **LiBwrt 6.12 NSS**，NSS 对 NAT 与 PPPoE 的接管最完整。
- 更在意内核版本与新特性：选 **ImmortalWrt 6.18 PPE**，不加载 NSS 固件，直连转发走 PPE 分载。
- 想要新内核又要 NSS：选 **VIKING 6.18 NSS**，代价是内存占用高于两个 6.12 版本。
- 偏好接近上游原样的系统：选 **LEDE 6.12 NSS** 或 **FanchmWrt 6.12 FWX**。
- **代理速度与版本无关**：HomeProxy/sing-box 的流量始终由 CPU 处理，硬件加速只作用于直连转发。

## 下载

在 [Releases](../../releases) 页面选择对应版本，下载前先确认标签后缀：

| 版本 | 标签后缀 |
|:---|:---|
| 6.12 NSS | `-zn-m2-libwrt-6.12-nss` |
| 6.18 PPE | `-zn-m2-immortalwrt-6.18-ppe` |

每次发布包含以下文件：

| 文件 | 用途 |
|:---|:---|
| `*-sysupgrade.bin` | 设备已运行 OpenWrt 时升级 |
| `*-factory.ubi` | 首次通过 U-Boot 刷入 |
| `SHA256SUMS` | 校验文件完整性 |

下载后建议先校验：

```bash
sha256sum -c SHA256SUMS
```

## 刷机

### 首次刷入（原厂固件）

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
3. 浏览器打开 `http://192.168.1.1`，这是 U-Boot 网页界面。
4. 选择「Update firmware」，上传 `*-factory.ubi`，等待约 3 分钟。

### 升级（已运行 OpenWrt）

通过 LuCI「系统 → 备份/升级」上传 `*-sysupgrade.bin`，或在 SSH 中执行：

```bash
sysupgrade -n /tmp/ZN-M2-*-sysupgrade.bin
```

**注意**

- 6.12 与 6.18 之间切换时不要保留配置，两者内核与加速栈不同。
- 同一版本内升级可以保留配置，密码、网络、代理设置都会保留。
- 刷机过程中不要断电。

### 救砖

| 症状 | 处理方式 |
|:---|:---|
| U-Boot 正常，系统无法启动 | 进入 U-Boot 网页重新刷入固件 |
| U-Boot 损坏 | 通过 TTL 串口重新写入 U-Boot |
| 完全无响应 | 使用编程器烧录 SPI Flash |

只要 U-Boot 未损坏，都可以通过 TFTP 恢复。刷机前建议备份原厂固件。

<details>
<summary>TTL 串口恢复</summary>

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

## 首次使用

| 项目 | 默认值 |
|:---|:---|
| 管理地址 | `192.168.1.1` |
| 用户名 | `root` |
| 密码 | 首次登录时设置 |
| 主机名 | `ZN-M2` |
| 界面语言 | 简体中文 |
| 界面主题 | Aurora |
| DHCP 地址池 | `192.168.1.100`–`192.168.1.249` |

- 保留配置升级会沿用原有地址与密码，管理地址不一定仍是 `192.168.1.1`。
- 固件不预置公开密码。首次进入 LuCI 后请立即设置 root 密码；设置之前 SSH 不接受空密码登录。
- WAN 口连接光猫或上级路由，LAN 口连接内网设备。

## 默认设置

### 网络

- **DHCP 预置**：开机时先写入 LAN 的 DHCP 地址段，再启动网络服务，避免首次启动时设备拿不到地址。地址段与 LAN 网段不一致时会自动放弃，不会下发错误地址。
- **DNS**：使用 WAN 下发的 DNS，缓存 8192 条，并发转发上限 300。
- **连接跟踪**：上限 16384，家用与代理场景有充足余量。

### 性能

- **拥塞控制**：BBR + fq。TCP 缓冲区上限 2 MiB，发送队列低水位 128 KiB。
- **内存压缩**：ZRAM 使用 lzo-rle，按可见内存的一半创建，约 96 MiB。仅在页面真正换出时占用内存。
- **内核内存**：未使用的无线子系统保留区被压缩到 16 MiB，为系统多释放约 39 MiB。
- **日志**：系统与内核日志缓冲区各 256 KiB，便于重启后排查。

### 转发加速

| 版本 | 默认状态 |
|:---|:---|
| 6.12 NSS | NSS 硬件转发开启，软件流量分载关闭 |
| 6.18 PPE | 硬件流量分载开启 |
| FanchmWrt | FWX / Shortcut-FE 开启 |

- **6.12 NSS 不要同时开启软件流量分载**。两者会争用同一条转发路径，可能导致丢包和性能下降。如确需开启，请在 LuCI「防火墙 → 流量分载」中手动打开并自行承担风险。
- 6.18 PPE 的硬件分载会让已卸载的连接绕过防火墙规则，按连接限速、标记与统计对这部分流量不生效。需要逐连接管控时请关闭分载。
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

- **健康检查**：确认 LAN 的 DHCP 服务、默认路由、DNS 解析、代理进程与可用内存。仅在需要时重启 `dnsmasq` 或 `homeproxy`，不会整机重启。可用内存低于 40 MiB 时只记录日志。
- **CoreMark**：结果写入 `/etc/bench.log`，并显示在 LuCI 概览页的 CPU 型号旁。IPQ6000 典型分数约 18000。
- **指示灯**：电源灯常亮，WAN 与 LAN 灯随链路状态变化；无 Wi-Fi 对应指示灯。

## 常见问题

**升级后地址变了或无法上网**

跨内核升级保留了旧配置时会出现。重新刷入并在升级时取消「保留配置」，或登录后检查 LAN 地址与 WAN 协议。

**6.12 和 6.18 怎么选**

只关心直连转发选 6.12 NSS；希望使用较新内核选 6.18 PPE。代理速度两者相同。

**内存显示只有 195 MiB 左右**

硬件为 256M 版本，部分内存被保留区与系统占用，剩余部分由 ZRAM 补充。

**支持 USB 吗**

不支持。此版本硬件无 USB 接口，固件也不包含 USB 驱动与存储工具。

**NSS 和流量分载能同时开吗**

不能。两者争用转发路径，同时开启可能导致丢包。6.12 NSS 默认已关闭软件分载。

**开了代理为什么没有变快**

硬件加速只处理直连转发，代理流量由 CPU 处理，速度取决于节点与 CPU。

**面板灯只亮电源灯**

刷入其他上游后可能出现灯名不一致。固件会在首次启动时按实际设备名纠正一次；若仍不亮，检查「系统 → LED 配置」中的设备名。

**实验版登录密码是什么**

以对应上游为准。LEDE 默认 `root` / `password`，登录后请立即修改。

**为什么升级后少了一些配置项**

固件会清理已不存在的软件包留下的配置，以及旧代理组件写入的 DNS 片段，避免影响现有网络。已安装软件包的配置不会被删除。

## 许可

本项目采用 MIT 许可证，见 [LICENSE](LICENSE)。固件包含的第三方组件遵循各自许可证，详见 [NOTICE.md](NOTICE.md)。

## 致谢

LiBwrt、ImmortalWrt、VIKINGYFY、LEDE、FanchmWrt、Aurora、HomeProxy、sing-box、gecoosac 及所有上游贡献者。
