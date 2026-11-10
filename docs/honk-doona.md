# honk + doona 透明代理方案

本文件记录把三条构建线（LiBwrt 6.12 NSS、ImmortalWrt 6.18 PPE、ImmortalWrt 6.18 NSS）的透明代理栈从 HomeProxy + sing-box 换成 [honk](https://github.com/daeuniverse/honk) 的方案。LEDE 6.12 NSS 与 FanchmWrt 6.12 FWX 不适用，原因见 [适用范围](#一适用范围与不适用范围)。

## 一、适用范围与不适用范围

| 构建线 | 内核 | 包管理 | 软件策略 | 本方案 |
|:---|:---|:---|:---|:---|
| LiBwrt 6.12 NSS | 6.12 | apk | `aurora-homeproxy` → `honk-doona` | 迁移 |
| ImmortalWrt 6.18 PPE | 6.18 | apk | `aurora-homeproxy` → `honk-doona` | 迁移 |
| ImmortalWrt 6.18 NSS | 6.18 | apk | `aurora-homeproxy` → `honk-doona` | 迁移 |
| LEDE 6.12 NSS | 6.12 | opkg | `aurora-homeproxy` | 不变 |
| FanchmWrt 6.12 FWX | 6.12 | apk | `upstream-native` | 不变 |

LEDE 无法迁移，有三条互相独立的硬障碍：

1. **内核层面被上游关闭。** `coolsnowwolf/lede` 的 `config/Config-kernel.in` 中 `KERNEL_DEBUG_INFO` 带 `depends on !TARGET_qualcommax`，而 honk 需要 `KERNEL_DEBUG_INFO_BTF`（依赖 `KERNEL_DEBUG_INFO`）。同时 `target/linux/qualcommax/config-6.12` 直写 `# CONFIG_BPF_SYSCALL is not set` 与 `# CONFIG_BPF_JIT is not set`，honk 连 eBPF 程序都无法加载。
2. **包格式不同。** LEDE 默认 `CONFIG_USE_APK` 为 n（opkg），而 daeuniverse 官方源只发布 apk。
3. **buildroot 无 Rust 交叉工具链。** LEDE 源码树没有 `package/lang/rust`，`coolsnowwolf/packages` 里的 rust 包是 `PKG_HOST_ONLY`（用 `x.py` 从源码构建 host rustc），也没有 `bpf-linker` 包。

FanchmWrt 从未包含 HomeProxy，属另一项独立工作，不在本方案范围内。

## 二、为什么可以共存 NSS / PPE 加速

honk 的数据面钩子在 **TC ingress/egress**（TCX，Linux 6.12+），比 netfilter 更早：

```
LAN 网卡收包
  ├─ TC ingress (honk)          ← honk 在此判定
  │    ├─ 判定「代理」→ 送入 daens 命名空间 → 用户态出站
  │    └─ 判定「直连」→ 返回 TC_ACT_OK，交还内核
  └─ netfilter PREROUTING → FORWARD → flowtable / ECM → POSTROUTING → 发送
```

由此得到两条结论：

- **代理流量**被 TC ingress 截走，进入 `daens` 命名空间，**不经过主机 POSTROUTING**，ECM 的 hook 看不到这些包，不存在语义冲突。代理流量本来就由 CPU 处理，与 sing-box 时期一致。
- **直连流量**由 honk 返回 `TC_ACT_OK` 交还内核（`doc/en/design/datapath.md` 的 route-time direct offload），**完整走内核转发路径**，NSS ECM 与 PPE flowtable 硬件分载照常生效。

因此 `files/usr/lib/zn-m2/acceleration-policy.sh` 的 `nss` / `ppe` 行为保持不变：`nss` 继续关闭软件 flow offloading（NSS 自己接管转发），`ppe` 继续在 flowtable 可用时开启 `flow_offloading` + `flow_offloading_hw`。

hnk 官方文档把「绕过 TC 的硬件加速路径」划在能力边界之外，指的是**已经**被加速的既有连接 honk 抓不到，需要 `restart ecm` 或重启回收；这不是「不能共存」。

需要实测确认的两点：

1. ECM 若加速了 dnsmasq 的上游 UDP DNS，honk 的 NFQUEUE（`nfqueue_enable: true`，固定 queue 320）看不到这些包，域名分流可能失效。
2. honk 在 `NF_INET_PRE_ROUTING`、priority -250 安装独占的 `inet honk_nfqueue` / `udp_decision` 表，只匹配 `l4proto UDP && mark & 0xc0000000 == 0xc0000000`。本仓库没有其他 NFQUEUE 使用者，mark 使用 30/31 位，与 fw4 的 mark 空间不冲突。

## 三、运行前置条件

honk 要求 Linux 6.12+，并需要以下内核能力。新增的全部内核符号集中在 `CONFIG_KERNEL_*`，通过 `include/kernel-defaults.mk` 的 `Kernel/Configure/Default` 转成内核的 `CONFIG_*`。

| 需求 | 满足方式 |
|:---|:---|
| BTF（`/sys/kernel/btf/vmlinux`） | `CONFIG_KERNEL_DEBUG_INFO=y` + `CONFIG_KERNEL_DEBUG_INFO_BTF=y`，并压制 `CONFIG_KERNEL_DEBUG_INFO_REDUCED` |
| cgroup v2 + `CONFIG_CGROUP_BPF` | `CONFIG_KERNEL_CGROUPS=y` + `CONFIG_KERNEL_CGROUP_BPF=y` |
| TCX（`NET_XGRESS`） | 由 `kmod-sched-core` 注入 `CONFIG_NET_CLS_ACT=y` 自动 select，无需手写 |
| NFQUEUE | `kmod-nft-queue` → `CONFIG_NFT_QUEUE`，`kmod-nfnetlink-queue` → `CONFIG_NETFILTER_NETLINK_QUEUE` |
| veth | `kmod-veth` |

### 三个必须写死的符号

`KERNEL_DEBUG_INFO_BTF` 的默认值在三条线上都不是 y：

- LibWrt：`default y if (… || TARGET_qualcommax || …) && BUILDBOT`，GitHub Actions 不设 `BUILDBOT`。
- VIKINGYFY：同一列表里**没有** `TARGET_qualcommax`，即使 `BUILDBOT` 也开不了。

更关键的是 `KERNEL_DEBUG_INFO_REDUCED` 默认为 `y if !(…) || !BUILDBOT`，而 `KERNEL_DEBUG_INFO_BTF` 带 `depends on KERNEL_DEBUG_INFO && !KERNEL_DEBUG_INFO_REDUCED`。**只写 `CONFIG_KERNEL_DEBUG_INFO_BTF=y` 会被依赖链静默丢弃**，必须同时显式关闭 reduced：

```
CONFIG_KERNEL_DEBUG_INFO=y
# CONFIG_KERNEL_DEBUG_INFO_REDUCED is not set
CONFIG_KERNEL_DEBUG_INFO_BTF=y
CONFIG_KERNEL_CGROUPS=y
CONFIG_KERNEL_CGROUP_BPF=y
```

`KERNEL_CGROUPS` 在 qualcommax 上默认就是 y（`target/linux/qualcommax/Makefile` 的 `FEATURES` 没有 `small_flash`），但显式写死，避免上游改默认值后静默失效。

`CONFIG_KERNEL_DEBUG_INFO_BTF` 的 `select DWARVES` 会自动引入 host 工具 `pahole`，无需手工处理。

### 为什么不用 `vmlinux-btf`

daeuniverse 的 `vmlinux-btf` 包只是把预生成的 BTF blob 打进去，其 `EXTRA_DEPENDS` 绑定到精确内核（`kernel (=$(LINUX_VERSION)~$(LINUX_VERMAGIC)-r$(LINUX_RELEASE))`）。自建内核对不上任何预编译 blob，只能让内核自己带 BTF。`vmlinux-btf-builtin` 是个空包，`preinst` 检查 `/sys/kernel/btf/vmlinux` 存在才放行——同样要求内核自带 BTF。

### 代价

内核带 DWARF + BTF 编译，构建时间约 +15~25 分钟，`vmlinux` 增大 1~2 MiB。

## 四、包来源

OpenWrt buildroot（含 apk 版 25.12）**只从 `package/` 与 `feeds/` 构建包，不能消费外部 apk 仓库**。因此 `CONFIG_PACKAGE_honk=y` 要生效，树里必须有 `package/honk/Makefile`。

本方案在仓库内新增 `package/honk/`，从官方 release 下载**预编译静态二进制**，不做 Rust 交叉编译：

```make
PKG_NAME:=honk
PKG_VERSION:=0.1.0-beta.6
PKG_SOURCE:=honk-core-v$(PKG_VERSION)-aarch64-unknown-linux-musl-stock-full.tar.gz
PKG_SOURCE_URL:=https://github.com/daeuniverse/honk/releases/download/v$(PKG_VERSION)
PKG_HASH:=d07e51a5c5c6b1cc734c096a48beb3c6a5e31816661047b8b49d3ac03a85dcc4
```

三个选择：

- **`-stock`**：system allocator 变体。官方文档明确 `stockalloc` 用于「Small devices where the RSS high-water mark matters more」，200 MB 设备必须选它。
- **`full`**：包含 native API 与内嵌 doona，`ui: 'embedded'` 才能工作。
- **静态链接**：release 二进制没有 `PT_INTERP`，不依赖 `libstdcpp` / `libgcc_s`，也没有 musl ABI 漂移问题。

这样不需要在 CI 安装 rustup、nightly 工具链、`bpf-linker`、cmake、libclang，`build-profile.yml` 的依赖列表保持原样。代价是无法给 honk 打源码补丁，只能通过 init/config 脚本定制。

## 五、doona 面板

doona 不是独立服务，是 honk `full` 构建内嵌进 `honk-core` 的静态前端，由 native API 在 `http://<LAN IP>:9527/` 提供。

- 必须用 IP 访问，honk 拒绝 `openwrt.lan` 这类主机名。
- 首次访问创建管理员账号，保存在 `data_dir/state/honk.db`，不在配置文件里。
- 默认防火墙不开放 WAN 侧 9527；需要进一步收紧可改 `listen: '127.0.0.1:9527'` 并用 `ssh -L`。
- `/lib/upgrade/keep.d/honk` 只保留 `/etc/honk/data/`，升级不丢账号与配置。
- doona 只支持 honk 的 native API，**不支持 dae**；honk 与 dae 抢同一组 `dae0` / `daens` 设备，不能同装。

本方案不安装 `luci-app-honk`，面板入口就是 doona。LuCI 侧只保留 `/etc/init.d/honk` 的启停能力（可通过命令行或后续再补页面）。

## 六、默认配置

新增 `package/honk/files/config.dae`，以官方默认为基础，改四处：

```dae
global {
    wan_interface: auto
    lan_interface: br-lan
    log_level: warning              # 官方 info；降低日志量以节省内存
    dial_mode: domain++
    auto_config_kernel_parameter: true
    data_dir: '/etc/honk/data'
    log_file: ''
    nfqueue_enable: true
    bootstrap_resolver: '1.1.1.1:53'
}

dns {
    upstream { local: 'udp://127.0.0.1:53' }
    routing { request { fallback: local } response { fallback: local } }
}

routing { fallback: direct }

experimental {
    native_api {
        enabled: true
        listen: '0.0.0.0:9527'
        password_auth: true
        config_write: true
        ui: 'embedded'
    }
    cache_file { enabled: true }
}
```

- 去掉整个 `clash_api` 块：doona 走 native API，Clash API 只服务 zashboard 一类面板，省一个监听端口与相关内存。
- `routing { fallback: direct }`：开箱不改变任何连通性，没配节点时就是纯直连路由。
- `auto_config_kernel_parameter: true` 会让 honk 自己设置 `net.ipv4.ip_forward=1`、各接口 `rp_filter=0`、`accept_local`、`route_localnet`，仓库里不需要再写这些 sysctl。ZN-M2 是双口路由，不是单臂网关，也不需要文档里那三项针对单臂网关的手工配置。

`/etc/config/honk` 使用 `store 'file'`：

```
config honk 'config'
	option config_file '/etc/honk/config.dae'
	option store 'file'
	option data_dir '/etc/honk/data'
```

`store 'db'` 会把配置存进 SQLite 并保留修订历史，但常驻内存明显更高，200 MB 设备不采用。

自动启停：honk 服务**默认停用**，与上游包一致。上游仍标注 alpha，且 honk#456 可能切断 LAN 侧访问路由器本机 TCP 服务，因此启用必须是显式动作：

```sh
/etc/init.d/honk enable
/etc/init.d/honk start
```

`/etc/honk/config.dae` 的 `routing { fallback: direct }` 保证启用后不配置节点也不产生代理流量。

## 七、体积预算

rootfs 分区为 `mtd16: 06080000`（101,187,584 B，约 96.5 MiB），是硬上限。

| 项目 | 变化 |
|:---|:---|
| 移除 `luci-app-homeproxy` + `luci-i18n-homeproxy-zh-cn` + `sing-box` | 约 −25 ~ −35 MiB（未压缩） |
| 新增 `honk-core`（静态，stock-full） | +30.9 MiB（30,872,776 B） |
| 新增 `v2ray-geoip`（`geoip.dat`） | +23.3 MiB |
| 新增 `v2ray-geosite`（`geosite.dat`） | +2.3 MiB |
| 内核 BTF 段 | +1 ~ 2 MiB |
| **净增（未压缩）** | **约 +30 ~ +35 MiB** |

现有镜像约 42 ~ 44 MB，squashfs 压缩后预计落在 62 ~ 70 MB，仍低于 96.5 MiB，但余量从约 50 MB 缩到 25 ~ 30 MB。

若实测装不下，第一顺位去掉 `v2ray-geoip`（省 23.3 MiB），代价是路由规则只能用 `geosite:` 与 `dip()`，不能用 `geoip:`。

## 八、内存预算

| 项目 | 数值 |
|:---|:---|
| 总内存 | 200 MB |
| 当前可用 | 约 99 MB |
| `honk-core` RSS 预估 | 50 ~ 90 MB |

监控与缓解：

- `-stock` 变体 + `store file` + 去掉 clash_api + `log_level: warning`，已是当前可选的最省组合。
- `files/usr/sbin/zn-m2-healthcheck` 的 `check_proxy()` 改为检查 `honk-core` 进程，进程消失时重启 `honk`。
- 首次启动的 cron 行在检测到 `/etc/init.d/honk` 时把 `MIN_MEM_KB` 从 40960 提到 49152，避免 honk 常驻后每 10 分钟刷低内存告警。

## 九、代码改动清单

### 新增

| 路径 | 说明 |
|:---|:---|
| `package/honk/Makefile` | 预编译二进制包，`PKG_HASH` 钉死 |
| `package/honk/files/honk.init` | 自写 procd 脚本（BTF 检查、挂载 bpffs、respawn） |
| `package/honk/files/honk.config` | `store 'file'` |
| `package/honk/files/config.dae` | 见 [默认配置](#六默认配置) |
| `scripts/zn-m2-honk-package.sh` | 把 `package/honk` 复制进源码树并做静态校验 |
| `tests/test-honk-package.sh` | 上述校验的回归测试 |
| `docs/honk-doona.md` | 本文件 |

### 修改

| 路径 | 改动 |
|:---|:---|
| `configs/zn-m2-libwrt-6.12-nss.config` | 加五条 `KERNEL_*`；删三条 homeproxy；加 `honk`、`v2ray-geoip`、`v2ray-geosite`、`kmod-sched-bpf` |
| `configs/zn-m2-immortalwrt-6.18.config` | 同上 |
| `configs/zn-m2-immortalwrt-viking-main-nss.config` | 同上 |
| `profiles/libwrt-25.12-nss.conf` | `SOFTWARE_POLICY=honk-doona` |
| `profiles/immortalwrt-viking-owrt-ppe.conf` | `SOFTWARE_POLICY=honk-doona` |
| `profiles/immortalwrt-viking-main-nss.conf` | `SOFTWARE_POLICY=honk-doona` |
| `scripts/load-profile.sh` | 允许 `honk-doona` |
| `scripts/experimental-build.sh` | `pin_native_feeds` / `stage_profile_files` / `apply_software_policy` / `verify_resolved_config` 增加 `honk-doona` 分支 |
| `scripts/validate-experimental-output.sh` | `honk-doona` 必需包 `honk v2ray-geoip v2ray-geosite luci-theme-aurora` |
| `scripts/release-notes.sh` | 三条线的代理说明改为 honk + doona |
| `libwrt-6.12.sh` | HomeProxy 块按 `INCLUDE_HONK` 与包策略跳过；新增 honk 包注入 |
| `immortalwrt-6.18.sh` | 同上 |
| `files/usr/sbin/zn-m2-healthcheck` | `check_proxy()` 增加 honk 分支 |
| `files-zn-m2/etc/uci-defaults/zz-mainrouter-stability.sh` | 不再强制 enable homeproxy；按 honk 存在与否选择内存阈值 |
| `.github/workflows/zn-m2-256m-main-router.yml` | `.config` 断言、manifest 必需包、内核 BTF 断言 |
| `.github/workflows/zn-m2-256m-6.18.yml` | 同上 |
| `.github/workflows/build-profile.yml` | 增加 `tests/test-honk-package.sh`；不需要 Rust 工具链 |
| `tests/test-package-source-contracts.sh`<br>`tests/test-healthcheck-hardening.sh`<br>`tests/test-profile-policy.sh`<br>`tests/test-experimental-*.sh`<br>`tests/test-release-notes.sh`<br>`tests/test-workflow-contracts.sh` | 按新策略调整断言 |
| `README.md`、`docs/multi-upstream.md`、`docs/README.md`、`docs/maintainers.md` | 代理说明、doona 访问方式、仓库结构 |

## 十、已知问题（已确认接受）

| 编号 | 现象 | 影响 |
|:---|:---|:---|
| [honk#456](https://github.com/daeuniverse/honk/issues/456) | LAN 客户端访问网关本机 TCP 服务全部超时（SSH/HTTP/HTTPS），ICMP 与 UDP 正常，`systemctl stop honk` 立即恢复；`direct(must)` 不能规避 | 若在 6.12.112 / 6.18 上复现，刷机后 LAN 侧无法访问 LuCI 与 SSH，必须准备原厂恢复路径 |
| [honk#476](https://github.com/daeuniverse/honk/issues/476) | 配置热重载的优雅关闭末尾报 `NFQUEUE listener failed: unexpected netfilter netlink message type 2`，进程退出，procd 约 5 秒后拉起 | doona 改配置并 reload 时高概率触发；数据面自动恢复，但会短暂中断 |
| [honk#453](https://github.com/daeuniverse/honk/issues/453) | `pname()` 为子串匹配，与 dae 的整名匹配不一致 | 进程名规则需写得更精确 |
| [honk#481](https://github.com/daeuniverse/honk/issues/481) | geodata 自动更新尚未提供配置项 | geo 数据需手工更新 |
| [honk#399](https://github.com/daeuniverse/honk/issues/399) | 节点级链式代理（dialer-proxy / detour）未实现 | 需要链式代理的场景不可用 |

honk 自身仍标注 **Early alpha**，所有 release 均为 Pre-release。`PKG_HASH` 钉死版本，升级需人工评估。

## 十一、实施与验证

### 阶段 0：单线试点（不进 Release）

只改 `immortalwrt-viking-main-nss`，手动派发一次构建，产物不上 Release。注意 honk 服务默认停用，第 6 步之前需要先执行 `/etc/init.d/honk enable && /etc/init.d/honk start`。刷机后按序验证：

1. `/sys/kernel/btf/vmlinux` 存在。
2. `/sys/fs/cgroup/cgroup.controllers` 含 `memory`。
3. `/proc/config.gz` 中 `CONFIG_DEBUG_INFO_BTF`、`CONFIG_CGROUP_BPF`、`CONFIG_NET_CLS_ACT`、`CONFIG_NFT_QUEUE` 均为 y。
4. `/etc/init.d/honk enable && /etc/init.d/honk start` 后 `pidof honk-core` 有输出，`dmesg` 无 verifier 拒绝。
5. `ip link show dae0` 与 `ip netns list` 出现 `daens`。
6. LAN 侧 `curl http://10.0.0.1/` 与 SSH 正常（#456 验证点）。
7. `http://10.0.0.1:9527/` 打开 doona，创建管理员账号。
8. 在 doona 中修改配置并 reload，重复 10 次，记录是否触发 #476。
9. 直连测速应仍接近千兆（ECM / flowtable 生效）。
10. 配置节点后代理生效，`curl ifconfig.me` 出口为节点地址。
11. 运行 30 分钟后 `ps` 查看 `honk-core` RSS。

#456 或 #476 任一严重复现则暂停后续阶段，重新评估。

### 阶段 1：另两条线跟进

`libwrt-6.12-nss` 与 `immortalwrt-viking-owrt-ppe`。PPE 线使用 fw4 flowtable + `flow_offloading_hw=1`（不是 ECM），且是唯一在 IPv6 上依赖 PPE 的线，需要单独验证 IPv6 分流。

### 阶段 2：文档与发布

三条线全部通过后更新 README、`docs/multi-upstream.md`、发布说明，并恢复定时发布。

### 回滚

改动全部在新分支上，`main` 不受影响。软件策略是开关式的：把 profile 里的 `SOFTWARE_POLICY` 从 `honk-doona` 改回 `aurora-homeproxy` 重新构建即可完全回到 HomeProxy。LEDE 线全程不动，天然是 HomeProxy 的对照组。
