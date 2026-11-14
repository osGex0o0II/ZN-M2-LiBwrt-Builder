# 维护者说明

本文件面向仓库维护者，说明构建、版本解析、缓存和发布流程。普通用户请阅读 [根目录 README](../README.md)。

## 工作流

| 工作流 | 作用 |
|:---|:---|
| `ZN-M2 LiBwrt 6.12 NSS` | 构建并发布 6.12 NSS 固件 |
| `ZN-M2 ImmortalWrt 6.18 PPE` | 构建并发布 VIKING owrt PPE 固件 |
| `ZN-M2 ImmortalWrt 6.18 NSS` | 实验线，构建并发布 VIKING main NSS 固件 |
| `ZN-M2 LEDE 6.18 NSS` | 实验线，构建并发布 LEDE 固件 |
| `ZN-M2 FanchmWrt 6.12 FWX` | 实验线，构建并发布 FanchmWrt 固件 |
| `Build ZN-M2 profile` | 三条实验线共用的构建流程 |
| `Publish ZN-M2 profile release` | 三条实验线共用的发布流程 |
| `Auto-merge dependency updates` | 两个验证构建通过后合并依赖更新 PR |
| `Prune Actions caches` | 清理过期缓存，控制仓库缓存总量 |
| Dependabot | 每周检查 GitHub Actions 版本，需人工合并 |

两个主力线工作流都会在 Pull Request 中运行构建，用于验证改动；PR 和推送 `main` 的构建只验证、不发布 Release。手动运行默认也不发布 Release；每周计划构建会发布独立 Release。

实验 VIKING main NSS、LEDE、FanchmWrt 的独立配置及构建验收见 [多上游维护说明](multi-upstream.md)。FanchmWrt 保留自己的界面和 FWX；现有源码固定文件名保留兼容。

## 版本固定

上游源码、feeds、主题和代理包的版本记录在五个文件中：

- `deps/libwrt-6.12.env`：LiBwrt 6.12 NSS 线。
- `deps/immortalwrt-6.18.env`：ImmortalWrt 6.18 PPE 线。
- `deps/immortalwrt-viking-main-nss.env`：ImmortalWrt 6.18 NSS 线。
- `deps/lede-master-nss.env`：LEDE NSS 线（内核由 LEDE master 决定）。
- `deps/fanchmwrt-25.12.env`：FanchmWrt 6.12 FWX 线。

每条线的构建前都会校验必需字段与 revision 格式，缺失或格式错误会直接失败。

## 依赖版本

仓库不在事后提交 pin，而是在**构建时解析**。

每个 `deps/*.env` 里有两组值：

- `*_TRACK=<repo-url>#<ref>`：声明要跟随的分支。
- `*_COMMIT=<sha>`：**离线回退值**，只在远端不可达时使用。

`scripts/resolve-latest-upstreams.sh` 在构建开始前把每个 `*_TRACK` 解析成当前分支 tip，覆盖同名的 `*_COMMIT`。如果没有 TRACK 条目（FanchmWrt 就是这种），则完全使用固定 pin。

| 构建线 | 是否跟随上游 |
|:---|:---|
| LiBwrt 6.12 NSS | 9 条 tracked |
| ImmortalWrt 6.18 PPE | 7 条 tracked |
| ImmortalWrt 6.18 NSS | 7 条 tracked |
| LEDE NSS | 6 条 tracked |
| FanchmWrt 6.12 FWX | 不跟踪，全部固定 |

因此**不需要定时任务来 bump pin**。提交进仓库的 `*_COMMIT` 数值只影响远端不可达时的降级行为；想复查某次构建实际用了什么，看 workflow 日志里 `sh scripts/resolve-latest-upstreams.sh` 的输出，或 release 里的 `feeds.buildinfo` 与 `BUILD-MANIFEST.txt`。

除 FanchmWrt 外，两条主力线与三条实验线都会在构建时跟随上游分支。FanchmWrt 的固定 pin 是有意的：它依赖用户自己的 fork，上游分支不会移动。

### Aurora 主题

`AURORA_COMMIT` 是**显式固定值，不参与自动跟踪**。上游把改动直接推到 master 而不发 tag，主题变更可能破坏 LuCI 布局，必须人工审查后再改这个值。`AURORA_TAG` 只作记录，构建使用的是 commit SHA。

### 自动合并

`auto-merge-deps.yml` 仍然监听依赖更新 PR（作者为 `github-actions[bot]`、GitHub Actions App 或仓库所有者，且只改 `deps/libwrt-6.12.env` 与 `deps/immortalwrt-6.18.env`，两个必需检查通过后合并）。但仓库里**没有**生成这类 PR 的定时任务，所以这个自动合并路径目前是空闲的；它只在有人手工提交纯 pin 变更 PR 时才会生效。

Dependabot 只覆盖 GitHub Actions 版本，每周一检查，不自动合并。

## 内核升级与 NSS 补丁

6.12 变体固定 LiBwrt 源码，内核小版本升级可能改变内核 API。升级 `OPENWRT_COMMIT` 后，如果 `qca-nss-ecm` 等 NSS 包编译失败，应优先在 `patches/qca-nss-ecm/` 增加兼容补丁，并在 `libwrt-6.12.sh` 中把补丁复制进 feed，而不是回退依赖更新。

例如 Linux 6.12.112 调整了 conntrack notifier ABI，同时 LiBwrt 使用 `CONFIG_NF_CONNTRACK_CHAIN_EVENTS` 分支；`0026-ecm-conntrack-notifier-kernel-6.12.112.patch` 同时覆盖两种 ABI，回归测试见 `tests/test-qca-nss-ecm-patch.sh`。

## 本地检查

在提交前至少运行：

```bash
sh tests/test-healthcheck-hardening.sh
sh tests/test-dhcp-primer.sh
sh tests/test-immortalwrt-6.18-contracts.sh
sh tests/test-workflow-contracts.sh
sh tests/test-package-source-contracts.sh
sh tests/test-upgrade-migrations.sh
sh tests/test-cpubench-hardening.sh
sh tests/test-uci-defaults.sh
sh tests/test-wired-hardware.sh
sh tests/test-dropbear-hardening.sh
sh tests/test-ecm-module-deps.sh
```

以下测试需要已解出的上游源码或 feed 目录：

```bash
sh tests/test-ppp-256m-patch.sh /path/to/openwrt
sh tests/test-upstream-defaults.sh /path/to/openwrt
sh tests/test-qca-nss-driver-patch.sh /path/to/nss-packages/qca-nss-drv
sh tests/test-qca-nss-ecm-patch.sh /path/to/nss-packages/qca-nss-ecm
```

同时检查：

```bash
python -c "import yaml,glob; [yaml.safe_load(open(p, encoding='utf-8')) for p in glob.glob('.github/workflows/*.yml')]"
for script in libwrt-6.12.sh immortalwrt-6.18.sh scripts/*.sh tests/*.sh; do bash -n "$script"; done
git diff --check
```

`tests/` 下共有 40 个脚本。上面列的是与固件行为直接相关的一批；`test-latest-upstreams.sh`、`test-honk-package.sh`（实验分支）等其余脚本同样应在提交前跑通，CI 的 `Run repository regression tests` 步骤会执行其中大多数。

部分测试依赖 Linux 环境的文件权限或路径行为；在 Windows 上运行出现权限相关失败时，以 CI 结果为准。

## 发布

- 6.12 与 6.18 使用独立的镜像名和 Release 标签，不能互相覆盖。
- 手动运行工作流时，`firmware_release=false` 只上传构建产物，不发布 Release。
- 计划构建会自动发布 Release，并保留最近的版本。
- 每条构建线只保留最新一份 Release 与产物，发布新版本时自动删除同线的旧版本。
- 发布前会校验镜像、设备树、软件包清单和 SHA256。

## 命名

- 构建线显示名统一为 `ZN-M2 <上游> <内核> <加速>`，例如 `ZN-M2 LiBwrt 6.12 NSS`。
- 只改显示名时不改 slug 与工作流文件名，避免历史 tag 与清理规则错位。
- Release 标题与构建线显示名一致，不带日期；版本信息只出现在 tag 中。
- tag 形如 `v<日期>.<run>.<attempt>-<slug>`，slug 已含 `zn-m2-` 前缀时不重复添加。
- 资产文件名保留完整版本信息，便于离线辨识。

## 缓存

`Prune Actions caches` 每天运行：

- 删除 PR 作用域和已退役版本的缓存。
- 每条构建线各保留最新的分支缓存。
- 仓库缓存总量超过 4GB 时，按最久未使用顺序清理。

## 文档

- 用户文档：根目录 `README.md`。
- 文档索引：`docs/README.md`。
- 历史设计记录：`docs/history/`，仅用于追溯，不作为当前操作指南。
- 许可证：`LICENSE` 和 `NOTICE.md`。


## 仓库结构

| 路径 | 用途 |
|:---|:---|
| `profiles/` | 每个固件版本的源码、分支、配置与适配器定义 |
| `configs/` | 各版本的软件包与内核选项 |
| `deps/` | 上游源码与 feed 的版本固定值，含跟踪分支 |
| `adapters/` | 各上游的构建适配脚本 |
| `libwrt-6.12.sh`、`immortalwrt-6.18.sh` | 两个正式版本的编译定制脚本 |
| `files/` | 通用定制文件，复制到所有正式版本 |
| `files-zn-m2/` | 256M 专属覆盖层，优先级高于 `files/` |
| `files-shared/` | 跨上游共享的配置清理与命名归一化 |
| `files-upstream-native/` | 使用上游软件栈的版本所需的默认项 |
| `patches/` | 内核、软件包与驱动补丁 |
| `scripts/` | 构建准备、产物校验与版本解析脚本 |
| `tests/` | 回归测试，构建前必须全部通过 |
| `docs/` | 用户指南、维护者文档与历史设计记录 |