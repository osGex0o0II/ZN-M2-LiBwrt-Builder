# 构建线

ZN-M2 No WIFI 提供四条原版构建线和三条 eBPF 测试变体。它们共享设备适配、纯有线边界和发布流程，但上游、内核与数据平面不同。

## 总览

| 构建线 | Profile ID | 上游 / 分支 | 内核 | 数据平面 | 界面与代理 | 定位 |
|---|---|---|---|---|---|---|
| **LiBwrt 6.12 NSS** | `libwrt-25.12-nss` | `LiBwrt/LibWrt` / `25.12-nss` | 6.12 | NSS + ECM | Aurora；HomeProxy + sing-box | 主力线，成熟软件栈与 NSS 转发 |
| **LiBwrt 6.12 NSS （eBPF）** | `libwrt-25.12-nss-ebpf` | `LiBwrt/LibWrt` / `25.12-nss` | 6.12 | NSS + ECM | Aurora；Honk + Doona | 测试，待真机验收 |
| **ImmortalWrt 6.18 PPE** | `immortalwrt-viking-owrt-ppe` | `VIKINGYFY/immortalwrt` / `owrt` | 6.18 | PPE + EDMA | Aurora；HomeProxy + sing-box | 主力线，降低 NSS 常驻开销 |
| **ImmortalWrt 6.18 PPE （eBPF）** | `immortalwrt-viking-owrt-ppe-ebpf` | `VIKINGYFY/immortalwrt` / `owrt` | 6.18 | PPE + EDMA | Aurora；Honk + Doona | 测试，待真机验收 |
| **ImmortalWrt 6.18 NSS** | `immortalwrt-viking-main-nss` | `VIKINGYFY/immortalwrt` / `main` | 6.18 | NSS + ECM | Aurora；HomeProxy + sing-box | 6.18 内核与 NSS 组合 |
| **ImmortalWrt 6.18 NSS （eBPF）** | `immortalwrt-viking-main-nss-ebpf` | `VIKINGYFY/immortalwrt` / `main` | 6.18 | NSS + ECM | Aurora；Honk + Doona | 测试，待真机验收 |
| **FanchmWrt 6.12 FWX** | `fanchmwrt-25.12` | `osGex0o0II/FanchmWrt` / `codex/zn-m2-25.12.6` | 6.12 | FWX / Shortcut-FE | 上游原生；不包含 HomeProxy | 保留上游原生界面与包集 |

Profile ID、工作流文件名和 Release tag slug 是稳定技术标识，含义与兼容规则见 [项目结构与命名](naming.md)。

## 如何选择

- **需要 NSS 转发、希望软件栈成熟稳定：** 选 LiBwrt 6.12 NSS。
- **希望降低 NSS 常驻开销、接受 PPE 数据平面：** 选 ImmortalWrt 6.18 PPE。
- **需要 6.18 内核与 NSS 组合：** 选 ImmortalWrt 6.18 NSS。
- **偏好上游原生 LuCI 与包集、不需要 HomeProxy：** 选 FanchmWrt 6.12 FWX。

全部构建线都面向纯有线配置。不同数据平面的实际差异、验证范围和性能数据见 [功能与边界](features.md) 与 [性能与内存](performance.md)。

## 验证状态

- 三条 eBPF 版独立构建。固件启动、管理访问、转发分载及原厂机型稳定性均待真机验收，见 [Honk + Doona](honk-doona.md)。

- LiBwrt 6.12 NSS 与 ImmortalWrt 6.18 PPE 是长期维护的主力线，构建、发布和主要功能路径已有持续验证。
- ImmortalWrt 6.18 NSS 与 FanchmWrt 6.12 FWX 使用共享 Profile 构建流程；已发布 Release，但不代表全部功能都已完成真机验收。
- 所有 Release 都附构建清单、源码提交和 SHA256；构建成功不等于设备验收完成。

## 共同边界

- 仅面向 ZN-M2，最低要求为原厂 256 MB 内存机型；1 GB 扩容机型已在真机验证，其他扩容容量以设备实际识别为准。
- 不提供 Wi-Fi 或 USB 功能；镜像中不包含对应驱动与固件。
- 跨构建线升级不保留配置。切换前先备份，并按 [安装与恢复](installation.md) 操作。
- 硬件加速只作用于符合条件的转发连接；HomeProxy / sing-box 的代理流量仍由 CPU 处理。
