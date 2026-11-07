# 回归测试

每个脚本独立运行，退出码 0 表示通过。

```sh
sh tests/test-workflow-contracts.sh </dev/null
```

在 Windows 的 Git Bash 里务必加 `</dev/null`：否则脚本可能继承交互式标准输入，`read` 会一直等待。

部分脚本需要已解出的上游源码树或 feed 目录，作为第一个参数传入；不传时它们会打印用法并以 2 退出，属预期行为。

## 工作流与仓库约定

| 脚本 | 校验内容 |
|:---|:---|
| `test-workflow-contracts.sh` | 构建线、必需检查、缓存配额、发布组件 |
| `test-workflow-subscriptions.sh` | 依赖自动合并订阅的工作流名 |
| `test-build-catalog.sh` | 五条构建线的显示名与 README 覆盖 |
| `test-profile-policy.sh` | profile 定义必填项与策略取值 |
| `test-profile-cache.sh` | 构建缓存 key 的构成 |
| `test-release-retention.sh` | 发布保留策略的 jq 选择器 |
| `test-latest-upstreams.sh` | 上游跟踪分支的解析 |

## 运行时文件与默认值

| 脚本 | 校验内容 |
|:---|:---|
| `test-uci-defaults.sh` | 首次启动脚本的编号与内容 |
| `test-runtime-defaults.sh` | ttyd、primer、健康检查的默认状态 |
| `test-upgrade-migrations.sh` | 保留配置升级时的迁移与幂等性 |
| `test-foreign-config-cleanup.sh` | 孤儿配置清理与已安装包的豁免 |
| `test-led-sysfs-normalize.sh` | LED sysfs 名在不同上游间的归一化 |
| `test-dhcp-primer.sh` | DHCP 预置文件的生成与清理 |
| `test-dhcp-primer-ipcalc.sh` | 退化版 `ipcalc` 下的网段计算 |
| `test-healthcheck-hardening.sh` | 内存与代理健康检查的阈值 |
| `test-dropbear-hardening.sh` | SSH 默认配置 |
| `test-cpubench-hardening.sh` | CoreMark 运行前后的资源约束 |
| `test-wired-hardware.sh` | 有线端口映射与网络默认值 |

## 构建适配与上游契约

| 脚本 | 校验内容 |
|:---|:---|
| `test-immortalwrt-6.18-contracts.sh` | 6.18 配置与包选择 |
| `test-package-source-contracts.sh` | 软件包来源与补丁引用 |
| `test-lede-adapter.sh` | LEDE 适配器的源契约（需源码树） |
| `test-lede-package-policy.sh` | LEDE 镜像的包裁剪 |
| `test-lede-netdevice-layout.sh` | 6.12 `netdevice.h` 布局与补丁（需 `gcc`、`clang`、源码树） |
| `test-viking-main-nss.sh` | ImmortalWrt NSS 线的源码契约（需源码树） |
| `test-fanch-native.sh` | FanchmWrt 原生软件栈的包选择（需源码树） |
| `test-fanch-port-order.sh` | FanchmWrt 端口标签与面板一致，硬件绑定不变（需源码树） |
| `test-experimental-prepare.sh` | 变体构建的准备阶段 |
| `test-experimental-package.sh` | 变体产物的文件构成 |
| `test-experimental-manifest.sh` | 变体产物的清单校验 |
| `test-experimental-logging.sh` | 构建日志的关键标记 |
| `test-ecm-start-order.sh` | ECM 服务在各上游下的启动顺序 |
| `test-luci-port-order.sh` | 状态页把 WAN 排在首位，两种 LuCI 布局与失败保护 |
| `test-ecm-module-deps.sh` | ECM 模块依赖声明 |
| `test-ppp-256m-patch.sh` | PPP 补丁（需源码树） |
| `test-qca-nss-driver-patch.sh` | NSS 驱动补丁（需 feed） |
| `test-qca-nss-ecm-patch.sh` | ECM 补丁（需 feed） |
| `test-upstream-defaults.sh` | 上游默认包集（需源码树） |

`verify-ecm-module-deps.sh` 与 `verify-nss-driver-symbols.sh` 是构建期调用的辅助脚本，由上面两个 `test-qca-nss-*` 间接覆盖。
