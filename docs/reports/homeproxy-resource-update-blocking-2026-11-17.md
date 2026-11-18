# HomeProxy「全部更新」失败并短时阻塞 LuCI 的复核报告

- 报告日期：2026-11-17
- 最后更新：2026-11-18
- 设备：ZN-M2（`qualcommax/ipq60xx`）
- 固件：ImmortalWRT SNAPSHOT `r0-51c575f`，kernel `6.18.60`
- HomeProxy：`luci-app-homeproxy-20261111-r1` / `sing-box-1.15.0_alpha13-r1`
- 上游仓库：[VIKINGYFY/packages](https://github.com/VIKINGYFY/packages)

## 摘要

在 HomeProxy 状态页点击「全部更新」后，页面先显示：

```text
未知错误：PermissionError: Download permission denied
```

随后 LuCI 页面短时间无法正常加载，资源版本显示为 `-`。约 3 分钟后页面自行恢复，旧规则文件仍在。

复核结论：

1. **直接触发**：更新脚本在查询 GitHub 版本时超时。`sing-geoip` 的 `releases/latest` 30 秒无响应，dashboard 的 atom feed 10 秒连接超时。脚本在「查版本」阶段就标记失败，没有进入实际下载。
2. **问题放大**：`resources_update` 同步执行 `update_resources.sh`，三项资源串行更新。三项版本查询都失败时总耗时约 3 分钟，超过 `uhttpd` 的 `network_timeout=30` / `script_timeout=60`，阻塞了 LuCI 的 RPC。
3. **次生错误**：更新期间 `resources_get` 拿不到数据，所以版本显示 `-`；日志查看的 `cgi-download` 在 `session_access` 阶段失败，`cgi-io` 返回 403 `Download permission denied`。更新结束后同一 LuCI 会话读取日志返回 200，说明 ACL 没有永久损坏。
4. **不是本仓库改动导致**：设备上的 `update_resources.sh`、`luci-app-homeproxy.json`、`luci.homeproxy` 与上游 `a90d3a6` 在 LF 归一化后逐字节一致；本仓库没有这些文件的 overlay 或 patch。
5. **没有证据表明更新脚本切断了 WAN/DNS**：WAN 在线时间、dnsmasq PID、系统日志都没有断线、重启或 OOM 记录。更可能是 LuCI 管理页面/RPC 被阻塞，造成「页面打不开」的观感。

上游已在 2026-11-17 发布修复（`e29f6bdd`，包版本 `20261117-r3`），把更新改为后台任务 + 前端轮询，并缩短版本查询超时。2026-11-18 已用该版本重建三条带 HomeProxy 的固件线并发布，见第 13 节。

## 1. 环境与版本

```text
Linux ZN-M2 6.18.60 #0 SMP Sun Nov 15 05:05:07 2026 aarch64 GNU/Linux
DISTRIB_ID='ImmortalWRT'
DISTRIB_RELEASE='SNAPSHOT'
DISTRIB_REVISION='r0-51c575f'
DISTRIB_TARGET='qualcommax/ipq60xx'
DISTRIB_ARCH='aarch64_cortex-a53'
```

已安装包：

```text
luci-app-homeproxy-20261111-r1
luci-i18n-homeproxy-zh-cn-20261111-r1
sing-box-1.15.0_alpha13-r1
```

设备加速策略：

```text
/etc/zn-m2-acceleration-policy = ppe
```

即对应构建线 **ZN-M2 ImmortalWrt 6.18 PPE**。

## 2. 复现步骤

1. 浏览器登录 LuCI：`http://192.168.10.1/`
2. 打开「服务 → HomeProxy → 状态」
3. 在「资源管理」点击「全部更新」
4. 观察页面与 HomeProxy 日志

现场现象：

- 资源列表三项：国内 IP 规则集、国内域名规则集、仪表盘
- 版本/源地址短暂显示 `-`
- HomeProxy 日志出现 `未知错误：PermissionError: Download permission denied`
- 页面短时间无响应，约 3 分钟后恢复
- 旧规则文件仍在，代理服务当前未运行（`main_node=nil`）

## 3. 现场时间线

设备本地时间（CST，UTC+8）：

```text
2026-11-17 15:47:27 [geoip_cn] Failed to get the latest version; continuing with other resources.
2026-11-17 15:48:30 [geosite_cn] Failed to get the latest version; continuing with other resources.
2026-11-17 15:49:13 [dashboard] Failed to get the latest version; continuing with other resources.
2026-11-17 15:49:13 [RESOURCES] Update failed for: geoip_cn,geosite_cn,dashboard.
```

结果文件 `/var/run/homeproxy/update_resources.result`：

```text
status=1
core_updated=0
dashboard_updated=0
updated=
failed=geoip_cn,geosite_cn,dashboard
```

三项资源各耗时约 60 秒，总计约 3 分钟；与 `curl --retry 3 --max-time 30` 的重试预算一致。

## 4. 更新脚本分析

上游文件：

```text
luci-app-homeproxy/root/etc/homeproxy/scripts/update_resources.sh
```

版本查询地址：

```sh
GEOIP_VERSION_URL="${GEOIP_VERSION_URL:-https://github.com/SagerNet/sing-geoip/releases/latest}"
GEOSITE_VERSION_URL="${GEOSITE_VERSION_URL:-https://github.com/SagerNet/sing-geosite/releases/latest}"
DASHBOARD_VERSION_URL="${DASHBOARD_VERSION_URL:-https://github.com/SagerNet/sing-box-dashboard/commits/gh-pages.atom}"
```

实际下载源：

```sh
GEOIP_SOURCE="${GEOIP_SOURCE:-https://cdn.jsdelivr.net/gh/SagerNet/sing-geoip@rule-set/geoip-cn.srs}"
GEOSITE_SOURCE="${GEOSITE_SOURCE:-https://cdn.jsdelivr.net/gh/SagerNet/sing-geosite@rule-set-unstable/geosite-cn.srs}"
DASHBOARD_SOURCE="${DASHBOARD_SOURCE:-https://codeload.github.com/SagerNet/sing-box-dashboard/zip/refs/heads/gh-pages}"
```

版本查询函数：

```sh
fetch_release_version() {
  local effective_url version
  effective_url="$(run_curl -fsSL --compressed --retry 3 --retry-all-errors \
    --retry-delay 1 --connect-timeout 10 --max-time 30 \
    -A "$USER_AGENT" -o /dev/null -w '%{url_effective}' "$1")" || return 1
  version="${effective_url##*/}"
  case "$version" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "$version"
}
```

关键行为：

- 先查版本，再决定是否下载；
- 版本查询失败直接 `mark_failed`，**不会尝试下载**；
- 三项串行执行；
- 每项最多 3 次重试，每次 30 秒，失败时总耗时约 3 分钟。

因此，实际可用的 jsDelivr/codeload 下载源没有被使用，失败发生在更早的 GitHub 版本查询阶段。

## 5. 网络实测

在设备上直接 curl，未经过 HomeProxy（当前没有运行中的节点）：

| 目标 | 结果 |
|---|---|
| `https://github.com/SagerNet/sing-geoip/releases/latest` | **30.002 秒超时，code=000** |
| `https://github.com/SagerNet/sing-geosite/releases/latest` | 302，0.46 秒 |
| `https://github.com/SagerNet/sing-box-dashboard/commits/gh-pages.atom` | **10.002 秒连接超时，code=000** |
| `https://cdn.jsdelivr.net/gh/SagerNet/sing-geoip@rule-set/geoip-cn.srs` | 200，0.20 秒 |
| `https://codeload.github.com/SagerNet/sing-box-dashboard/zip/refs/heads/gh-pages` | 200，1.27 秒 |

补充测试：

| 目标 | 结果 |
|---|---|
| `https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-geoip` | 200，0.63 秒，含 `20261112` 等版本 |
| `https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-geosite` | 200，2.23 秒，最新 `20261116043813` |
| `https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box-dashboard` | 200，但 `versions` 为空；dashboard 在 `gh-pages` 分支，没有 release tag |

结论：

- 现场 GitHub 的部分端点不可达/超时，是本次更新的直接触发因素；
- jsDelivr 和 codeload 的实际下载源可达；
- 对 geoip/geosite，可以用 jsDelivr package API 作为版本查询回退；dashboard 需要用 codeload 的 `ETag`/`Last-Modified` 或本地哈希。

## 6. LuCI 超时与阻塞分析

设备配置：

```text
uhttpd.main.script_timeout  = 60
uhttpd.main.network_timeout = 30
uhttpd 启动参数：-t 60 -T 30
rpcd：/sbin/rpcd -s /var/run/ubus/ubus.sock -t 30
luci.sauth.sessiontime = 3600
```

上游 `luci.homeproxy` 的 `resources_update`：

```ucode
resources_update: {
  call: function() {
    ...
    const status = system(`${update_proxy}${HP_DIR}/scripts/update_resources.sh`);
    ...
  }
}
```

这是**同步执行**：脚本跑完，RPC 才返回。三项都失败时约 3 分钟，超过 `uhttpd` 的 30/60 秒超时。

高置信推断的因果链：

```text
点击“全部更新”
  → resources_update 同步执行 update_resources.sh
  → GitHub 版本查询超时 + retry，约 3 分钟
  → rpcd/uhttpd 被长任务占用
  → resources_get 超时/失败，版本显示 “-”
  → 日志轮询的 cgi-download 在 session_access 阶段失败
  → cgi-io 返回 403 “Download permission denied”
  → 页面表现为“未知错误”+ 短时无法加载
```

说明：更新期间没有做并发抓包，因此“rpcd/uhttpd 被阻塞”标为高置信推断；更新失败、日志 403、恢复后 200 都是实测事实。

## 7. 日志读取与 ACL 复核

`status.js` 的日志查看：

```js
return fs.read_direct(String.format('%s/%s.log', hp_dir, filename), 'text');
```

该请求最终由 `/cgi-bin/cgi-download` 处理，`cgi-io` 先检查：

```c
session_access(sid, "cgi-io", "download", "read")
```

失败即返回 403 `Download permission denied`；之后才检查目标文件路径。

设备 ACL：

```text
/usr/share/rpcd/acl.d/luci-app-homeproxy.json
```

已包含：

- `file`：`/var/run/homeproxy/homeproxy.log`
- `file`：`/var/run/homeproxy/sing-box-c.log`
- `file`：`/var/run/homeproxy/sing-box-s.log`
- `ubus`：`luci.homeproxy.resources_get`、`resources_update` 等

没有显式声明 `cgi-io: ["download"]`。但 root 用户会通过基础 ACL 获得 `cgi-io.download`。

实测：

| 场景 | 结果 |
|---|---|
| 未认证/无授权 session 调 `cgi-download` | 403 `Download permission denied`（size 27） |
| 手动 grant `cgi-io download` + `file` 日志 read 后 | 200，379 bytes |
| 新建 root session | ACL 含 `cgi-io.download` 和日志 path，`cgi-download` 200，379 bytes |
| 更新结束后现有 LuCI Web 会话 | `session access` 两项 true，`cgi-download` 200，379 bytes |

因此：

- 截图里的 403 不是 ACL 被删除；
- 更新结束后同一 Web 会话读取日志正常；
- 403 是更新期间会话检查失败的次生结果；
- 对非 root/受限会话，给应用 ACL 补 `cgi-io: ["download"]` 仍是合理的加固。

## 8. 设备文件与上游一致性

设备文件 SHA256：

```text
/etc/homeproxy/scripts/update_resources.sh
042f6cb829cf123dc0e600d5f7893630798aa4becc4661c68eb9254185d6cc4a

/usr/share/rpcd/acl.d/luci-app-homeproxy.json
fbaf133d330b7172f483da2d8ad5a9961f2508af2260905add3e5e8895266558

/usr/share/rpcd/ucode/luci.homeproxy
33957c6a877c03e1569032cb3f833f2b01a7c2495a1e4dd7a658e4a3587fa9eb
```

上游 `VIKINGYFY/packages` 提交 `a90d3a6ae36f3bedc26c4397c8211a4afc9d8fc5` 对应文件，LF 归一化后：

```text
update_resources.sh  042f6cb829cf123dc0e600d5f7893630798aa4becc4661c68eb9254185d6cc4a
acl.json             fbaf133d330b7172f483da2d8ad5a9961f2508af2260905add3e5e8895266558
luci.homeproxy       33957c6a877c03e1569032cb3f833f2b01a7c2495a1e4dd7a658e4a3587fa9eb
```

三者与设备完全一致。

说明：

- 通过 GitHub API 在 Windows 落盘的上游文件是 CRLF，直接哈希会不同；归一化为 LF 后一致。
- `status.js` 设备上是 8849 bytes 的压缩产物（`jsmin`），上游源码是 11012 bytes；不能直接比较哈希，但设备首行是标准 LuCI 压缩形式，不是本项目改写的版本。

## 9. 为什么不是本项目修改导致

在本项目仓库中检索：

```text
git ls-files | grep -i homeproxy
→ 无结果
```

仓库没有：

- `/etc/homeproxy/scripts/update_resources.sh`
- `/usr/share/rpcd/ucode/luci.homeproxy`
- `/usr/share/rpcd/acl.d/luci-app-homeproxy.json`
- `/www/luci-static/resources/view/homeproxy/status.js`
- 对应的 overlay 或 patch

本项目实际只做：

- 在四个 `configs/*.config` 中选择 `luci-app-homeproxy` / i18n；
- 在 `scripts/profile-build.sh` 中从 `VIKINGYFY/packages` feed 安装 HomeProxy；
- `files/usr/sbin/zn-m2-healthcheck` 中的 HomeProxy 健康检查；
- `files-zn-m2/etc/uci-defaults/zz-mainrouter-stability.sh` 中的 `homeproxy enable`。

这些都没有修改 HomeProxy 的脚本、ACL、ucode 或前端。

补充：

- `zn-m2-healthcheck` 在 `main_node=nil` 且 `server.enabled=0` 时直接返回，不会重启 HomeProxy；
- 本次事件中 `main_node=nil`，因此健康检查不是触发因素；
- `zz-mainrouter-stability.sh` 只设置 `uhttpd.main.max_requests='8'`，没有改 `script_timeout`、`network_timeout` 或 ACL。

## 10. 上游代码变更

关键提交：

```text
a90d3a6ae36f3bedc26c4397c8211a4afc9d8fc5
refactor: HomeProxy 统一资源更新入口
2026-11-10T07:11:18Z
```

该提交：

- 移除独立“更新规则库”按钮；
- 移除 `resources_update` 的 `scope` 参数；
- 移除脚本的 `UPDATE_SCOPE` 分支；
- 统一为一次「全部更新」；
- `resources_update` 继续同步执行 `system(...)`。

父提交 `e6e9679` 仍有：

```ucode
resources_update: {
  args: { scope: 'scope' },
  call: function(req) {
    const scope = req?.args?.scope || 'all';
    if (!(scope in ['all', 'rules']))
      return { status: 1 };
    ...
    const status = system(`${update_proxy}${HP_DIR}/scripts/update_resources.sh ${scope}`);
```

新提交把这条“只更新规则库”的快速路径删除了，导致一次同步调用固定串行跑 geoip、geosite、dashboard 三项。

## 11. 根因与责任划分

### 已确认

- 更新失败发生在版本查询阶段；
- GitHub `sing-geoip` latest 和 dashboard atom 当时超时；
- jsDelivr/codeload 的实际下载源可达；
- 更新结果文件 `status=1`，三项全部 `failed`；
- 旧规则文件未丢失；
- 更新结束后同一 Web 会话读取日志 200；
- 设备文件与上游 `a90d3a6` 后端文件逐字节一致；
- 本项目仓库没有 HomeProxy 文件或 patch；
- WAN 在线、dnsmasq 未重启、无 OOM/panic。

### 高置信推断

- `resources_update` 同步执行约 3 分钟，超过 `uhttpd` 超时；
- 长任务占用 `rpcd`/`uhttpd`，导致 `resources_get` 失败、版本显示 `-`；
- 日志 `cgi-download` 的 `session_access` 在阻塞期间失败，返回 403；
- 页面“无法加载”主要是 LuCI 管理页面/RPC 被阻塞。

### 未证实

- 当时外网网站是否同时不可用；现有日志没有 WAN/DNS 断线证据；
- 更新期间 rpcd 的精确阻塞时长（没有并发抓包）。

### 责任划分

| 责任方 | 责任 |
|---|---|
| 上游 `VIKINGYFY/packages` | 主责。`a90d3a6` 将资源更新做成同步长任务，只依赖 GitHub 版本查询，没有超时预算、后台化或回退。 |
| 现场网络 | 直接触发。GitHub 部分端点超时；jsDelivr/codeload 可达。 |
| 本项目 | 选型/验收责任，不是代码责任。选择并默认启用了该上游包，自动跟踪 `main`，但未在真机回归这条“全部更新”路径。 |

## 12. 上游修复

上游已于 2026-11-17 发布修复：

```text
e29f6bdd32d99bcfa6fe46881b2190977a192b82
fix: Keep HomeProxy resource updates responsive
```

配套提交：

```text
774295aefe2da0b9577adfff7ef0a935e7cc5018
fix: Run HomeProxy network diagnostics asynchronously

a6abaaa3fd97031cd65709fed24dcc21a47f5b75
fix: Restore HomeProxy certificate uploads and TLS access
```

包版本：

```text
luci-app-homeproxy-20261117-r3
```

修复内容：

- `resources_update` 改为 `update_resources.sh --background`，立即返回；
- 新增 `resources_update_status` RPC；
- `resources_get` 返回更新状态；
- `UPDATE_BUDGET=180` 总预算；
- 版本查询网络上限从 30 秒降到 8 秒；
- 下载最多 2 次、每次最多 60 秒；
- `flock` 防止重复任务；
- 结果文件原子写入，包含 `running/job_id/pid/started_at/phase/core_updated/dashboard_updated/apply_failed/error`；
- 前端每 2 秒轮询，区分成功、部分失败、超时、任务中断、已在运行；
- dashboard reload 移到 worker 结束时处理。

仍未加入：

- jsDelivr API 版本回退；
- dashboard 的 `ETag`/`Last-Modified` 回退；
- ACL 的 `cgi-io: ["download"]`。

所以 GitHub 版本查询不可达时，更新仍会失败；但会快速失败、保留旧规则，不再阻塞页面。

## 13. 2026-11-18 重建验证

从构建提交 `72b39b699d89c465c7633a695ed3342ee8b52f56` 重新构建了三条带 HomeProxy 的固件线。构建清单记录的上游固定提交：

```text
VIKINGYFY_COMMIT=272bfa963063cf6d02aa9454850b24cd2e319691
```

三条线最终 rootfs manifest 均包含：

```text
luci-app-homeproxy - 20261117-r3
luci-i18n-homeproxy-zh-cn - 20261117-r3
```

构建运行：

| 构建线 | Run |
|---|---|
| ZN-M2 LiBwrt 6.12 NSS | <https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/actions/runs/44211936995> |
| ZN-M2 ImmortalWrt 6.18 PPE | <https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/actions/runs/44211672064> |
| ZN-M2 ImmortalWrt 6.18 NSS | <https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/actions/runs/44211937192> |

FanchmWrt 6.12 FWX 的配置不包含 HomeProxy，本次未重建。

已发布镜像：

| 构建线 | Release tag | 发布时间（UTC） |
|---|---|---|
| ZN-M2 LiBwrt 6.12 NSS | `v2026.11.18.496.1-zn-m2-libwrt-6.12-nss` | 2026-11-18T02:56:59Z |
| ZN-M2 ImmortalWrt 6.18 PPE | `v2026.11.18.184.1-zn-m2-immortalwrt-6.18-ppe` | 2026-11-18T02:57:27Z |
| ZN-M2 ImmortalWrt 6.18 NSS | `v2026.11.18.26.1-zn-m2-viking-6.18-nss` | 2026-11-18T02:04:01Z |

镜像 SHA256 与 Release 资产 digest 一致；PPE 当前为 GitHub `Latest`。

设备升级说明：

- 测试设备仍运行 `luci-app-homeproxy-20261111-r1`；
- 设备对应 PPE 线，升级应使用 `ImmortalWrt-2026.11.18.184.1-ZN_M2-NOWIFI-256M-6.18-PPE-sysupgrade.bin`；
- 同线升级可保留配置；
- 升级后确认包版本为 `20261117-r3`，再测试“全部更新”；
- 点击后应显示“更新中”或立即返回，不再卡住数分钟；
- GitHub 不可达时应在约 8 秒内失败并保留旧规则；
- 日志查看不应再出现 `Download permission denied`。

## 14. 建议

### 14.1 上游

1. 保持后台任务 + 轮询模型；
2. geoip/geosite 版本查询增加 jsDelivr API 回退；
3. dashboard 使用 codeload 的 `ETag`/`Last-Modified` 或本地哈希；
4. ACL 增加 `cgi-io: ["download"]`，覆盖非 root/受限用户；
5. 前端在长任务超时时明确显示“仍在后台执行”，不要显示“未知错误”；
6. 失败时保留旧规则并在页面标注最后成功版本。

### 14.2 本项目的可选补丁

- 在 `update_resources.sh` 中保留 8 秒版本查询上限，并加入 jsDelivr 回退；
- 给 `luci-app-homeproxy.json` 补 `cgi-io: ["download"]`；
- 若上游未合并，可对 `resources_update` 增加 `timeout` 包裹作为额外保险；
- 在真机构建验收中加入“GitHub 不可达时点击全部更新”的回归项。

## 15. 复现/验证命令

设备端：

```sh
# 版本查询（单次，无重试）
curl -fsSL --connect-timeout 10 --max-time 30 \
  -o /dev/null -w 'code=%{http_code} time=%{time_total}\n' \
  https://github.com/SagerNet/sing-geoip/releases/latest

# 实际下载源
curl -fsSL --connect-timeout 10 --max-time 30 \
  -o /dev/null -w 'code=%{http_code} time=%{time_total}\n' \
  https://cdn.jsdelivr.net/gh/SagerNet/sing-geoip@rule-set/geoip-cn.srs

# 资源状态
ubus call luci.homeproxy resources_get

# 更新结果与日志
cat /var/run/homeproxy/update_resources.result
cat /var/run/homeproxy/homeproxy.log
```

上游：

```sh
git clone https://github.com/VIKINGYFY/packages.git
cd packages
git show a90d3a6:luci-app-homeproxy/root/etc/homeproxy/scripts/update_resources.sh
git show a90d3a6:luci-app-homeproxy/root/usr/share/rpcd/ucode/luci.homeproxy
git show a90d3a6:luci-app-homeproxy/root/usr/share/rpcd/acl.d/luci-app-homeproxy.json
```

## 16. 结论

- 本次失败的直接原因是 GitHub 版本查询端点超时；
- 页面卡顿/`Download permission denied` 是同步长任务超过 `uhttpd` 超时后的次生现象；
- ACL、规则文件和 WAN/DNS 都没有永久损坏；
- 上游 `a90d3a6` 的同步“全部更新”设计是主因；
- 本项目没有修改 HomeProxy 代码，只负责选型、默认启用和上游跟踪；
- 上游 `20261117-r3` 已修复阻塞问题，三条带 HomeProxy 的固件线已完成重建并发布，设备刷入 PPE 新镜像后即可验证。

## 附录 A：设备文件哈希

```text
042f6cb829cf123dc0e600d5f7893630798aa4becc4661c68eb9254185d6cc4a  /etc/homeproxy/scripts/update_resources.sh
fbaf133d330b7172f483da2d8ad5a9961f2508af2260905add3e5e8895266558  /usr/share/rpcd/acl.d/luci-app-homeproxy.json
33957c6a877c03e1569032cb3f833f2b01a7c2495a1e4dd7a658e4a3587fa9eb  /usr/share/rpcd/ucode/luci.homeproxy
```

## 附录 B：上游链接

- 仓库：<https://github.com/VIKINGYFY/packages>
- 问题引入提交：<https://github.com/VIKINGYFY/packages/commit/a90d3a6ae36f3bedc26c4397c8211a4afc9d8fc5>
- 修复提交：<https://github.com/VIKINGYFY/packages/commit/e29f6bdd32d99bcfa6fe46881b2190977a192b82>
- 异步诊断：<https://github.com/VIKINGYFY/packages/commit/774295aefe2da0b9577adfff7ef0a935e7cc5018>
- 证书/TLS 修复：<https://github.com/VIKINGYFY/packages/commit/a6abaaa3fd97031cd65709fed24dcc21a47f5b75>

## 附录 C：镜像 SHA256

```text
LiBwrt factory:
ac8e35d38d78546dbcc6196854fdc16497c2a4a532705cdc8ec5e33c24fdc634

LiBwrt sysupgrade:
41d3977167179486a1e919b22707b279fc2e358d8534caa2fafafc6d6a986653

PPE factory:
8d8f8b4ce61a3a4a4be7df5ef1ddb0393e9caf550ce910bd55e9a986457a1e5a

PPE sysupgrade:
d269b3f7b72394e4fe8338a253889cf97dc36875906685bd3d5edc71f91a42e6

Viking NSS factory:
4a2dd0a3b587a4889d8ec1320cba09729ecc16ee1dd482f96b7f9cc1540ceb52

Viking NSS sysupgrade:
13ee202acad780daf22e2dd7f0ebb942d5841c12b4626dac5367d9f1093027cd
```
