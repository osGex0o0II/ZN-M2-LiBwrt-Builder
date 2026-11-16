# 维护者说明

本文件说明 ZN-M2 固件的构建、依赖管理和发布流程。普通用户请阅读 [项目 README](../README.md)。

## 工作流

| 构建线 | 工作流文件 | 手动发布参数 |
|:---|:---|:---|
| LiBwrt 6.12 NSS | `zn-m2-256m-main-router.yml` | `firmware_release` |
| ImmortalWrt 6.18 PPE | `zn-m2-256m-6.18.yml` | `firmware_release` |
| ImmortalWrt 6.18 NSS | `zn-m2-256m-viking-nss.yml` | `publish` |
| FanchmWrt 6.12 FWX | `zn-m2-256m-fanchmwrt-fwx.yml` | `publish` |

前两条构建线在各自的工作流中执行完整构建，统一调用 `publish-mature.yml` 发布与清理旧版本；后两条使用 `build-profile.yml` 和 `publish-profile.yml`。

手动触发默认不发布 Release，只有启用对应参数才会发布。每周计划构建可自动发布；前两条在 Pull Request 中还执行构建验证。不要把构建 Artifact 与公开 Release 混为一谈。

## Profile 与依赖

| 路径 | 作用 |
|:---|:---|
| `profiles/` | 上游、配置、适配器和软件策略 |
| `configs/` | 软件包与内核选项 |
| `deps/` | 上游跟踪引用及备用的固定提交 |
| `adapters/` | 实验构建线的适配代码 |
| `patches/` | 驱动、软件包及内核补丁 |
| `files/`、`files-zn-m2/` | 项目定制的运行时配置 |
| `files-shared/` | 跨上游共享的迁移与命名修正 |
| `files-upstream-native/` | 上游原生软件栈的少量默认项 |
| `scripts/` | 构建、版本解析、验证与发布 |
| `tests/` | 回归测试 |

`deps/*.env` 中的 `*_TRACK` 声明跟踪的仓库与分支，`*_COMMIT` 在对应远端引用不可用时作为回退值。构建时，`scripts/resolve-latest-upstreams.sh` 解析可用的最新提交。

| 构建线 | 版本策略 |
|:---|:---|
| LiBwrt 6.12 NSS | 构建时跟踪部分上游 |
| ImmortalWrt 6.18 PPE | 构建时跟踪部分上游 |
| ImmortalWrt 6.18 NSS | 构建时跟踪部分上游 |
| FanchmWrt 6.12 FWX | 固定提交，不自动跟踪 |

因此 `deps/*.env` 不一定直接等于某次已发布构建的全部实际版本。核查时应结合构建日志及对应的 buildinfo。Aurora 的 `AURORA_COMMIT` 单独固定，不参与上述自动跟踪。

## 依赖更新

`auto-merge-deps.yml` 可在符合提交者、路径及必需检查条件时合并依赖更新 PR，但仓库当前没有自动生成此类 pin 更新 PR 的定时工作流。Dependabot 用于更新 GitHub Actions 依赖，不能代替固件上游版本管理。

内核更新后若 NSS 或 ECM 驱动遇到 API 兼容问题，应核查实际源码提交，并在 `patches/` 保留有测试覆盖的修正；避免单凭版本号推断兼容性。

## 验证

提交前至少执行与改动范围有关的回归测试，例如：

```bash
sh tests/test-release-notes.sh
sh tests/test-workflow-contracts.sh
sh tests/test-dependency-tracking.sh
sh tests/test-profile-policy.sh
sh tests/test-uci-defaults.sh
sh tests/test-wired-hardware.sh
git diff --check
```

需要完整覆盖时，检查 `tests/` 中所有实际存在的脚本及其参数要求；部分测试需提供上游源码或 feed 目录，不能直接无参数执行。

工作流的 YAML、Shell 语法及真机行为均需分别验证。文本与静态脚本测试通过不等于固件已成功构建或通过设备验收。

## 发布

- 对外只发布该构建线的 `*-factory.ubi`、`*-sysupgrade.bin`。
- `scripts/release-notes.sh` 负责生成中文发布说明及两份镜像的 SHA256。
- 构建线标签与镜像文件名须保持一致，不得跨 Profile 混用。
- 各构建线的 Release 独立管理；旧版本清理按各自工作流逻辑执行。
- 仅因 README 修改而创建的 PR 不应在未验证的情况下触发固件发布。

## 命名与文档

构建线显示名统一为 `ZN-M2 <上游> <内核> <加速>`。修改显示名不应同时随意修改工作流文件名、标签 slug 或必需检查名称。

- 用户入口：[README](../README.md)
- 安装与恢复：[installation.md](installation.md)
- 性能记录：[performance.md](performance.md)
- 多上游适配：[multi-upstream.md](multi-upstream.md)
- 历史记录：[history/](history/)，仅用于追溯旧设计，不作为当前操作规范
- 许可：[LICENSE](../LICENSE) 与 [NOTICE.md](../NOTICE.md)

## 分级 PR 验证

每个 Pull Request 都会运行 `.github/workflows/pr-validation.yml` 的快速校验。为兼容现有 `main` 分支保护，以下两个必需检查名称保留不变：

- `Build ZN-M2 LiBwrt 6.12 NSS`
- `Build ZN-M2 ImmortalWrt 6.18 PPE`

它们现为**汇总 Gate**，并不意味着每个 PR 都实际编译两次固件。真正执行交叉编译的 Job 使用 `Compile` 前缀。Gate 必须验证改动分类和快速回归测试成功；若分类要求构建某条固件线，则必须拿到该构建线实际构建成功的结果，异常跳过、失败或分类缺失都视为失败。

`scripts/ci-change-scope.py` 根据 Git 差异识别四条固件线：

- 纯文档、测试、发布说明以及仅修改 Release 元数据的 PR，只需快速验证。
- 固件配置、独立构建脚本等 Profile 专属改动，只编译受影响的构建线。
- 共享配置、公共补丁和未识别路径保守地要求相关或全部构建线验证。
- Viking NSS、FanchmWrt FWX 在对应路径变化时使用 `build-profile.yml` 真实编译，结果由 LiBwrt Gate 汇总。

编译前先执行快速测试，避免简单的测试断言错误浪费长时间构建。正式固件的发布仍由各条构建线在 `main` 上的定时、手动或固件代码变更触发；仅修改 `tests/**`、发布说明或 README 不会再次启动完整构建。

分类器自身的测试位于 `tests/test_ci_change_scope.py`。新增构建输入路径时应同步更新分类器与 `on.push.paths`，并为路径归属补充回归测试。不要把新工作流的整体验证结果与硬件实机验收混为一谈。

GitHub 保护规则仍由仓库设置管理。**在确认新 Gate 的实际检查结果前，不能删除或改名上述两个必需检查名称。**
