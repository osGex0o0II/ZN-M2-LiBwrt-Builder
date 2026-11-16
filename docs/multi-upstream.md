# 多上游构建与验收

适用于兆能 ZN-M2 原厂 256 MB 版本。四条构建线在上游、加速栈和运行时配置上相互独立；**构建成功与发布 Release 均不等于通过完整真机验收**。

## 构建线

| Profile | 源码 | 加速 | 软件策略 |
|:---|:---|:---|:---|
| `libwrt-25.12-nss` | LiBwrt `25.12-nss` | NSS + ECM | Aurora / HomeProxy |
| `immortalwrt-viking-owrt-ppe` | VIKINGYFY `owrt` | PPE + EDMA | Aurora / HomeProxy |
| `immortalwrt-viking-main-nss` | VIKINGYFY `main` | NSS + ECM | Aurora / HomeProxy |
| `fanchmwrt-25.12` | 项目维护的 FanchmWrt 分支 | FWX / Shortcut-FE | 上游原生 |

前两条使用独立的主力工作流；后两条使用共享实验构建流程。实验配置可以发布 Release，但仍需分别完成设备实测。

## 版本解析

`profiles/*.conf` 定义源码、配置、适配器及软件策略；`deps/*.env` 记录上游提交和跟踪分支。

- LiBwrt 与两条 ImmortalWrt 构建线使用 `*_TRACK`，在构建时解析远端分支的提交，失败时退回 `*_COMMIT`。
- FanchmWrt 不配置 `*_TRACK`，采用固定提交。
- Aurora 使用显式 `AURORA_COMMIT`，不参与自动跟踪。
- 构建日志与随构建生成的元数据用于核查实际 revision；不能只依据仓库当前的 pin 文件推断某次已发布镜像。

详见 [维护者说明](maintainers.md)。

## 配置边界

`adapters/` 处理各上游的构建差异；`configs/` 定义裁剪、软件包和内核选项；`patches/` 存放必要补丁。

- `files/`、`files-zn-m2/` 向主力构建线提供项目定制的运行时配置。
- 实验的 ImmortalWrt NSS 同样引入 Aurora / HomeProxy 软件策略及相应文件。
- FanchmWrt 使用 `files-upstream-native/`，保留上游主题与服务配置；首次启动脚本会启用 `fastnat`，并非完全不修改默认状态。
- `files-shared/` 包含跨上游共享的配置清理与设备命名归一化。

NSS 必须保留适用的固件内存区域；PPE 不加载 NSS 固件，不能将 PPE 的内存布局调整直接复用到 NSS 构建线。

## 网口与界面

ZN-M2 面板顺序为 WAN、LAN1、LAN2、LAN3。FanchmWrt 适配器修正设备树中 `lan1` 与 `lan3` 的标签差异；不得因此改变 PHY 绑定和交换机端口映射。

`scripts/zn-m2-luci-port-order.sh` 调整 LuCI 状态面板的显示顺序。显示顺序与实际物理端口绑定是两项不同的验证工作。

`zn-m2-diagnostics` 报告构建身份、内核、内存和相关模块状态；加载模块不等于加速命中。PPE/EDMA 也可能内建于内核，不能仅凭 `lsmod` 推断是否存在。

## 构建与发布

- LiBwrt 6.12 NSS、ImmortalWrt 6.18 PPE：分别通过独立工作流构建，手动发布开关为 `firmware_release`。
- ImmortalWrt 6.18 NSS、FanchmWrt 6.12 FWX：调用 `build-profile.yml` 构建，并通过 `publish-profile.yml` 发布；手动开关为 `publish`。
- 实验构建的计划任务也可自动发布 Release，不能再将其描述为“仅保存七天 Artifact”。
- 对外 Release 仅提供对应的 `factory.ubi` 与 `sysupgrade.bin`；校验摘要写入发布说明。内部构建记录可能包含更多验证资料。

不同 Profile 使用独立的镜像命名和发布标签。不得将一条构建线的镜像按另一条构建线的名称发布。

## 真机验收

1. 验证构建配置、目标 DTB、软件包和必要的驱动依赖。
2. 检查冷启动、管理访问、WAN/LAN 端口、MAC 地址、LED 和 NAND/UBI。
3. 验证同线升级、跨线无配置升级及恢复方式。
4. 测试 DHCP、PPPoE、IPv6、代理共存、加速命中、内存压力及持续运行。

PPE 默认配置硬件 flow offload，并在缺少相关内核支持时回退为关闭。NSS 构建线关闭竞争性软件分载。FanchmWrt 按其 FWX / fastnat 路径验证，不因存在某个 Qualcomm 软件包就标记为完整 NSS。

历史测试数据见 [性能与内存测试](performance.md)；刷机风险见 [安装与恢复](installation.md)。
