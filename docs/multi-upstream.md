# ZN-M2 多上游维护

范围为原厂 256M、纯有线、无 USB 的 ZN-M2。设备支持、加速策略、上游软件与构建发布分别维护。源码适配通过不表示镜像已通过真机启动、升级或加速测试。

| profile | 来源 | 软件 | 验证路线 |
|---|---|---|---|
| libwrt-25.12-nss | LiBwrt 25.12-nss | Aurora/HomeProxy | 既有构建线 |
| immortalwrt-viking-owrt-ppe | VIKING owrt | Aurora/HomeProxy | 既有构建线，PPE 策略暂保持保守 |
| immortalwrt-viking-main-nss | VIKING main | Aurora/HomeProxy | 实验，固定源码及 feeds |
| lede-master-nss | LEDE master，默认 6.12 | Aurora/HomeProxy | 实验，补充网络与 NAND 处理 |
| fanchmwrt-25.12 | 用户 FanchmWrt fork | 原生界面/FWX | 实验，原生设备移植 |

## 职责

`profiles/*.conf` 指定来源、分支、pin 文件、config、adapter、加速与软件策略。`scripts/load-profile.sh PROFILE` 输出元数据，缓存按完整 profile 区分；内核版本由源码读取。新实验 pin 需人工审核更新，不纳入现有两条构建线的依赖自动合并。

`adapters/` 只负责上游硬件接口差异。NSS 需要自己的保留内存；禁止复用 PPE 的 NSS 内存清零补丁。LEDE 的网络和升级分派只修改 ZN-M2 分支。FanchmWrt adapter 只验证源码 fork 中设备支持已存在，设备 DTS、端口、LED、镜像及 NAND 升级均在源码 fork 维护。

`scripts/experimental-build.sh` 复用 clone/prepare/build/package 流程，保留各上游原始 feed 来源并固定 revision。Aurora/HomeProxy 仅用于对应软件策略。FanchmWrt 不覆盖主题、FWX、原生 UCI、服务或加速设置，只添加只读 `zn-m2-diagnostics` 和构建身份。

`zn-m2-diagnostics` 读取构建身份、内核、内存及已加载相关模块，不重启服务、不写 UCI。PPE/EDMA 可能内建，不能用模块列表缺失推定驱动不存在；加速状态需要 nft flowtable、硬件流表和命中计数等现场证据。

## 构建与产物

`Validate new ZN-M2 upstreams` 调用共享 `build-profile.yml`，按 VIKING main NSS、LEDE、FanchmWrt 顺序运行。手动输入可选单个 profile；实验分支的 push 顺序运行全部。所有实验仅生成七天 artifact，无 Release 发布权限和步骤。

构建后检查最终 ZN-M2 DTB 的 Q6 和 NSS/platform 保留区，以及 package manifest 中无线/USB 排除和软件/驱动存在性。打包只接受唯一 ZN-M2 factory/sysupgrade；核验源 profiles.json 的 SHA256，再重命名并同步 JSON，最后生成完整 SHA256SUMS。不同 profile 不共用产物目录。

产物附完整 config、上游 buildinfo、源码与 builder SHA、feeds、加速/软件策略及实验状态。历史公开 Release 不重命名，不重写二进制；新 PPE 清理规则只处理新后缀。

## 验收顺序

1. 固定源码/feeds，执行 adapter 与板级脚本测试。
2. 在 Linux 完成 defconfig、DTB、依赖闭包和完整固件构建。
3. 在有恢复手段的设备上验证冷启动、每个物理端口、MAC、LED、NAND/UBI、升级与恢复。
4. 验证 DHCP、PPPoE、IPv6 PD、代理共存、加速命中与内存压力/持续运行。

只有对应实测通过后才提升发布状态。PPE 默认开启硬件 flow offload（`flow_offloading=1` + `flow_offloading_hw=1`）：6.18 no-NSS 真机 4 路并发 NAT 实测设备 CPU 由 8.3% 降至约 0.1%，开关两种状态下同一区间 SHA256 一致，PPE 计数器无失败/拒绝/完成错配；内核缺少 `nf_flow_table`/`nft_flow_offload` 时策略脚本自动回退为关闭。NSS 不开启竞争 flowtable。FanchmWrt 使用原生策略，不凭 qca-nss-dp 包名标为完整 NSS。

仓库展示名称已改为多上游构建器。远端仓库改名和必需检查改名应在构建链验证后单独迁移；当前保留旧 URL 和旧 check context，避免阻塞尚未合并的 PR。
