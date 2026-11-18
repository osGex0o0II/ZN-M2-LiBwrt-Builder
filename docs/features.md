# 功能与边界

ZN-M2 No WIFI 的组件大多来自上游 OpenWrt、ImmortalWrt、LiBwrt、FanchmWrt 与 VIKINGYFY 软件源。本项目的价值在选型、固定、集成、默认值、验证与交付，而不是把上游能力包装成自研。

## 数据平面

| 数据平面 | 使用构建线 | 加速对象 | 不加速的部分 |
|---|---|---|---|
| NSS + ECM | LiBwrt 6.12 NSS、ImmortalWrt 6.18 NSS | 符合条件的 IPv4 / IPv6 转发连接 | 代理进程、部分特殊流量与未命中规则的连接 |
| PPE + EDMA | ImmortalWrt 6.18 PPE | 以太网转发路径，降低 NSS 常驻开销 | 代理进程与未命中加速路径的连接 |
| FWX / Shortcut-FE | FanchmWrt 6.12 FWX | 上游支持的转发快路径 | 代理进程与上游未覆盖的连接 |

硬件加速解决的是“转发”而不是“代理”。HomeProxy / sing-box 的流量仍要经过 CPU，不能用直连吞吐量推断代理性能。

## 软件与插件

| 能力 | 三条 Aurora 线（LiBwrt / PPE / Viking NSS） | FanchmWrt 6.12 FWX |
|---|---|---|
| 管理界面 | Aurora + 简体中文 | 上游原生界面 |
| 代理 | HomeProxy + sing-box | 不包含 HomeProxy，以上游包集为准 |
| 远程接入 | ZeroTier、WoL、UPnP | 以上游包集为准 |
| 运维 | ttyd、autoreboot、gecoosac、package-manager | 以上游包集为准 |
| 内存压缩 | ZRAM，`lzo-rle` | 以上游配置为准 |
| 默认值 | 健康检查、UCI 迁移、LuCI 端口顺序 | 以 FanchmWrt 适配为准 |

具体软件版本以对应 Release 的构建清单和 rootfs manifest 为准；不同构建线不保证包集完全一致。

## 运行时加固

- **健康检查：** 周期性检查 DHCP、默认路由、DNS、代理状态与内存压力，异常时按策略恢复。
- **ZRAM：** 使用 `lzo-rle`，在低内存设备上减少换页压力；它不是物理内存扩容。
- **UCI 迁移：** 升级时处理旧配置键，减少跨版本配置失效。
- **LuCI 端口顺序：** 固定网口显示顺序，避免不同内核枚举顺序导致误判 WAN / LAN。
- **默认值收敛：** 管理地址、DNS、代理端口和防火墙行为由构建配置统一，而不是依赖用户手工设置。

这些机制的目标是减少常见故障，不替代备份、刷机前校验和真机验收。

## 上游与本项目

| 范围 | 上游 | 本项目 |
|---|---|---|
| 内核、驱动、数据平面 | OpenWrt / ImmortalWrt / LiBwrt / FanchmWrt | 选型、固定提交、适配 DTS 与镜像 |
| LuCI、HomeProxy、sing-box | 上游与 VIKINGYFY 软件源 | 选择包源、固定版本、默认配置、集成验证 |
| 构建 | 上游 SDK / ImageBuilder 流程 | 四条构建线、缓存、构建清单、发布门禁 |
| 发布 | GitHub Releases | 资产命名、SHA256、发布说明、保留策略 |

## 交付

- 四条构建线各自有独立工作流与发布流程。
- 每次构建生成 `BUILD-MANIFEST.txt`，记录上游仓库、分支、提交、内核、配置与适配器哈希。
- Release 附带 factory / sysupgrade 镜像与 SHA256；发布门禁要求构建成功、资产校验通过。
- 发布说明区分“构建完成”和“真机验收完成”，不把前者写成后者。
