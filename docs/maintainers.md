# 维护者说明

本文件面向仓库维护者，说明构建、版本固定、自动更新、缓存和发布流程。普通用户请阅读 [根目录 README](../README.md)。

## 工作流

| 工作流 | 作用 |
|:---|:---|
| `ZN-M2 LiBwrt 6.12 NSS` | 构建并发布 6.12 NSS 固件 |
| `ZN-M2 ImmortalWrt 6.18 no NSS` | 构建并发布 6.18 no NSS 固件 |
| `Auto-update pinned dependencies` | 每日检查上游版本并创建依赖更新 PR |
| `Auto-merge dependency updates` | 两个验证构建通过后合并依赖更新 PR |
| `Prune Actions caches` | 清理过期缓存，控制仓库缓存总量 |
| Dependabot | 每周检查 GitHub Actions 版本，需人工合并 |

两个固件工作流都会在 Pull Request 中运行构建，用于验证改动；PR 和推送 `main` 的构建只验证、不发布 Release。手动运行默认也不发布 Release；每周计划构建会发布独立 Release。

## 版本固定

上游源码、feeds、主题和代理包的版本记录在两个文件中：

- `deps/libwrt-6.12.env`：6.12 LiBwrt 及 NSS 相关版本。
- `deps/immortalwrt-6.18.env`：6.18 ImmortalWrt、feeds 和代理包版本。

更新依赖时，两个文件应保持各自的完整字段。构建前会校验必需字段和固定版本格式，缺失或格式错误会直接失败。

## 依赖自动更新

`Auto-update pinned dependencies` 每日执行：

1. 查询上游仓库的最新提交或稳定版本。
2. 更新两个 `deps/*.env` 文件。
3. 创建依赖更新 PR。
4. 触发 6.12 和 6.18 两个固件构建。

自动合并条件：

- PR 作者为 `github-actions[bot]`、GitHub Actions App 或仓库所有者（`osGex0o0II`）。
- 只修改 `deps/libwrt-6.12.env` 和 `deps/immortalwrt-6.18.env`。
- 6.12 与 6.18 两个必需检查均为成功。
- 合并时锁定已验证的提交。

自动合并只覆盖纯依赖 pin 更新。若修复需要同时修改构建脚本、补丁或测试，PR 不再命中自动合并白名单，必须在两个检查通过后手动 squash 合并。

仓库需要配置 `AUTO_UPDATE_TOKEN`，并授予触发 workflow 的权限，否则自动更新 PR 可能无法启动验证构建。

Dependabot 提交的 Actions 版本更新不会被自动合并，需要人工审查。

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
sh tests/test-packages-feed-patches.sh
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
bash -n libwrt-6.12.sh
bash -n immortalwrt-6.18.sh
git diff --check
```

部分测试依赖 Linux 环境的文件权限或路径行为；在 Windows 上运行出现权限相关失败时，以 CI 结果为准。

## 发布

- 6.12 与 6.18 使用独立的镜像名和 Release 标签，不能互相覆盖。
- 手动运行工作流时，`firmware_release=false` 只上传构建产物，不发布 Release。
- 计划构建会自动发布 Release，并保留最近的版本。
- 发布前会校验镜像、设备树、软件包清单和 SHA256。

## 缓存

`Prune Actions caches` 每天运行：

- 删除 PR 作用域和已退役版本的缓存。
- 6.12 与 6.18 分别保留最新的分支缓存。
- 仓库缓存总量超过 8GB 时，按最久未使用顺序清理。

## 文档

- 用户文档：根目录 `README.md`。
- 文档索引：`docs/README.md`。
- 历史设计记录：`docs/history/`，仅用于追溯，不作为当前操作指南。
- 许可证：`LICENSE` 和 `NOTICE.md`。
