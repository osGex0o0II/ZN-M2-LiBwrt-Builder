# 项目结构与命名

本文件定义构建线、目录和发布标识的命名规则。用户功能说明见 [项目 README](../README.md)，构建与发布流程见 [维护者说明](maintainers.md)。

## 产品名

对外产品名固定为 `ZN-M2 No WIFI`。`No WIFI` 不翻译、不加括号；正文可以用“纯有线”描述形态，但不把它作为名称的一部分。

构建线显示名仍为 `ZN-M2 <上游> <内核> <加速>`，不要把产品名重复写入构建线名。

## 构建线身份

对外显示名统一为：

```text
ZN-M2 <上游> <内核> <加速>
```

例如 `ZN-M2 LiBwrt 6.12 NSS`。显示名用于 README、Release 标题和工作流名称，不用于构造缓存键或程序路径。

每条构建线还有四类技术标识：

| 标识 | 用途 | 稳定性 |
|:---|:---|:---|
| Profile ID | `profiles/*.conf` 的 `PROFILE_ID`，用于构建产物、缓存和日志命名 | 高；修改会影响缓存与 Artifact |
| 工作流文件名 | GitHub Actions 入口，也是外部链接的一部分 | 高；修改会影响 Actions URL |
| 输入文件 | `deps/`、`configs/`、`adapters/` 中的对应文件 | 中；随 Profile 一起迁移 |
| Release tag slug | 对外版本标签的构建线后缀 | 高；旧 Release 清理依赖它 |

仓库名不在上表之内：它属于展示层标识，GitHub 对改名前后的地址保留重定向，因此重命名不影响构建、缓存或已发布资产。

## 当前映射

现有构建线包含历史命名，不能仅按显示名推断文件名：

| 显示名 | Profile ID | 工作流 | 依赖文件 | 配置 | 适配器 | Release tag slug |
|:---|:---|:---|:---|:---|:---|:---|
| ZN-M2 LiBwrt 6.12 NSS | `libwrt-25.12-nss` | `zn-m2-256m-main-router.yml` | `deps/libwrt-6.12.env` | `configs/zn-m2-libwrt-6.12-nss.config` | `adapters/libwrt-6.12.sh` | `zn-m2-libwrt-6.12-nss` |
| ZN-M2 ImmortalWrt 6.18 PPE | `immortalwrt-viking-owrt-ppe` | `zn-m2-256m-6.18.yml` | `deps/immortalwrt-6.18.env` | `configs/zn-m2-immortalwrt-6.18.config` | `adapters/immortalwrt-6.18.sh` | `zn-m2-immortalwrt-6.18-ppe` |
| ZN-M2 ImmortalWrt 6.18 NSS | `immortalwrt-viking-main-nss` | `zn-m2-256m-viking-nss.yml` | `deps/immortalwrt-viking-main-nss.env` | `configs/zn-m2-immortalwrt-viking-main-nss.config` | `adapters/immortalwrt-viking-main-nss.sh` | `zn-m2-viking-6.18-nss` |
| ZN-M2 FanchmWrt 6.12 FWX | `fanchmwrt-25.12` | `zn-m2-256m-fanchmwrt-fwx.yml` | `deps/fanchmwrt-25.12.env` | `configs/zn-m2-fanchmwrt-25.12.config` | `adapters/fanchmwrt-25.12.sh` | `zn-m2-fanchmwrt-6.12-fwx` |

`25.12` 是 OpenWrt 版本线，`6.12`/`6.18` 是内核版本，两者含义不同。现有 Profile ID 中的 `25.12` 属于历史命名，保留是为了不改变缓存键和已有构建记录。

## 内存容量与 256M 标识

- 最低要求为原厂 256 MB 内存机型。
- 1 GB 扩容机型已在真机验证。
- 其他扩容容量以设备实际识别为准，不在文档或发布说明中承诺具体上限。
- `256M` 仅作为历史技术键保留在工作流文件名、部分内部标识和旧 Release 资产名中；它不是产品定位或容量上限。
- 自 2026-11-18 起，新镜像文件名不再包含 `256M`；旧 Release 不回溯改名。

## 新构建线命名

新增构建线统一使用键：

```text
<upstream>-<kernel>-<acceleration>
```

- `upstream` 使用项目名：`libwrt`、`immortalwrt`、`fanchmwrt`，不使用分支名。
- `kernel` 使用 Linux 主次版本：`6.12`、`6.18`。
- `acceleration` 使用小写：`nss`、`ppe`、`fwx`。
- 键全部小写，以连字符分隔；不使用空格、下划线或 `v` 前缀。
- 仅当同一上游、内核和加速栈下存在两个需要区分的软件策略时，才追加策略后缀。

新构建线应派生以下文件：

| 对象 | 规则 | 示例 |
|:---|:---|:---|
| Profile | `profiles/<key>.conf` | `profiles/immortalwrt-6.18-nss.conf` |
| 依赖 | `deps/<key>.env` | `deps/immortalwrt-6.18-nss.env` |
| 配置 | `configs/zn-m2-<key>.config` | `configs/zn-m2-immortalwrt-6.18-nss.config` |
| 适配器 | `adapters/<key>.sh` | `adapters/immortalwrt-6.18-nss.sh` |
| 工作流 | `zn-m2-<key>.yml` | `zn-m2-immortalwrt-6.18-nss.yml` |
| Release tag | `v<date>.<run>.<attempt>-zn-m2-<key>` | `v2026.11.17.1.1-zn-m2-immortalwrt-6.18-nss` |

现有两条主力构建线的工作流文件名（`main-router`、`6.18`）和 Profile ID 属于兼容标识，不要求按新规则回改。新增或迁移构建线时，一次只改一层，并同步测试和发布清理逻辑。

## 镜像文件名

自 2026-11-18 起，发布资产使用以下名称：

| 构建类型 | 规则 | 示例 |
|:---|:---|:---|
| 主力构建线 | `LiBwrt-<version>-ZN_M2-NOWIFI-<kernel>-<acceleration>-factory.ubi` | `LiBwrt-2026.11.18.496.1-ZN_M2-NOWIFI-6.12-NSS-factory.ubi` |
| 主力构建线 | `ImmortalWrt-<version>-ZN_M2-NOWIFI-<kernel>-<acceleration>-factory.ubi` | `ImmortalWrt-2026.11.18.184.1-ZN_M2-NOWIFI-6.18-PPE-factory.ubi` |
| 共享 Profile 线 | `ZN-M2-NOWIFI-<profile>-<kernel>-<version>-factory.ubi` | `ZN-M2-NOWIFI-immortalwrt-viking-main-nss-6.18.55-<version>-factory.ubi` |

`sysupgrade.bin` 使用相同前缀。两条主力工作流与 `scripts/profile-package.sh` 已切换到新名称；本次变更需通过一次四条线构建验证。`256M` 仅保留在旧 Release 资产名、工作流文件名和历史文档中。

## 目录职责

| 路径 | 职责 |
|:---|:---|
| `profiles/` | 构建线入口：源码、分支、依赖、配置、适配器和软件策略 |
| `deps/` | 上游跟踪引用和固定回退提交 |
| `configs/` | 软件包、内核选项和裁剪规则 |
| `adapters/` | 上游之间的构建差异适配；新适配器统一放在此目录 |
| `patches/` | 驱动、软件包及内核补丁 |
| `files/`、`files-zn-m2/` | 项目定制的运行时配置 |
| `files-shared/` | 跨上游共享的迁移与命名修正 |
| `files-upstream-native/` | 上游原生软件栈的少量默认项 |
| `scripts/` | 构建、版本解析、验证和发布脚本 |
| `tests/` | 静态契约、分类器和运行逻辑回归测试 |
| `docs/` | 用户、维护者和历史文档；`docs/history/` 不作为当前规范 |

所有适配器统一位于 `adapters/`，包括 `adapters/libwrt-6.12.sh` 和 `adapters/immortalwrt-6.18.sh`。新增适配器不得再放到仓库根目录。

## 脚本与 Job 命名

- Shell 回归测试：`tests/test-<topic>.sh`。
- Python unittest：`tests/test_<module>.py`。
- 构建期辅助校验：`scripts/verify-<topic>.sh`。
- 主力构建 Job：`Compile <显示名>`；共享 Profile 构建 Job：`Build <显示名>`；PR 汇总 Gate：`Build <显示名>`；发布 Job：`Publish <显示名> release`。
- 其中两个 `Build <显示名>` Gate 是 `main` 分支保护的必需检查，名称视为稳定接口。

## 兼容规则

1. 不因修改显示名而重命名已有 Release tag slug；历史 Release 清理和外部下载链接依赖该后缀。
2. 不随意重命名 `main` 分支保护中的必需检查：`Build ZN-M2 LiBwrt 6.12 NSS`、`Build ZN-M2 ImmortalWrt 6.18 PPE`。
3. 重命名 Profile ID 会改变缓存命名空间和构建产物名，应单独提交并预期首次构建无缓存。
4. 重命名工作流文件会改变 Actions URL；必须同步 README、文档、测试和分支保护后再执行。
5. 新文件、新 Release 和新文档使用内核口径；`25.12` 只作为现有 Profile/文件的历史标识保留。
6. 删除工作流、脚本或测试前先检索引用，并运行 `tests/test-workflow-contracts.sh`、`tests/test-build-catalog.sh` 等相关回归测试。
7. 新文档和用户文案不再使用“ZN-M2 有线固件”或“256M 有线版”；旧 Release、历史文档和历史资产名保持原样。
