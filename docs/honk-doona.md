# Honk + Doona 测试变体

LiBwrt 6.12 NSS、ImmortalWrt 6.18 PPE、ImmortalWrt 6.18 NSS 都有独立 eBPF 变体。变体沿用相应基线的板级、内核和转发策略，使用 Honk 0.1.0-beta.6 和内嵌 Doona 0.1.0-rc.6。初次交叉编译完成后仍需逐条做真机验收。

## 启停与管理

- 出厂默认停止 Honk。先保存现有配置和原版镜像，通过 LuCI「服务 → Honk 代理」显式启动。确认管理连接正常后再选择开机自启。
- Doona 在受信任的 LAN 上通过路由器 IP 和 9527 端口访问。LuCI 页面提供跳转入口。首次打开 Doona 时创建管理员。
- 内附防火墙只允许 `br-lan` 和 loopback 使用该端口。自建受信任的 VLAN 或 LAN 接口时，同步评估 Honk 配置和 `/etc/nftables.d/30-zn-m2-honk.nft`。
- 默认分流为直连。NFQUEUE 默认关闭，Honk 的上游 DNS 与 dnsmasq 分离。出厂 `dns.routing.response` 使用 `fallback: accept`：把响应 fallback 指向与请求 fallback 相同的上游会触发 honk 的 requery cycle 保护，整机 DNS 在启动约 10 秒后全部变成 SERVFAIL。接入自己的节点、订阅和规则后再次验证 DNS、TCP、UDP 和 IPv6。
- 规则文件为 `/etc/honk/config.dae`，管理员状态在 `/etc/honk/data/`。同线保留配置升级后复核这两个位置及防火墙设置。

## 维护验证

先在 256 MB 原厂设备验收 PPE，再验证 LiBwrt NSS、ImmortalWrt NSS。每条线与同一组上游依赖的原版做对照，分别记录直连、代理吞吐、硬件分载计数、Honk RSS 和可用内存。

| 项目 | 验收内容 |
|---|---|
| 首次启动和可恢复性 | 冷启动、首次获得 DHCP、LuCI/SSH 和 Doona、关闭 Honk 恢复直连。准备串口或兼容 U-Boot 的恢复路径 |
| DNS 与分流 | 未缓存的域名、域名规则、IPv4/IPv6、DNS 超时恢复、TCP、UDP/QUIC 和调整规则后的新旧连接。`dns.routing.response` 的 fallback 不能指向与请求 fallback 相同的上游，否则 honk 报 `DNS response requery cycle` 并对所有名称返回 SERVFAIL；PPE 真机（6.18.60，beta.6）已复现并确认 `fallback: accept` 可修复 |
| 运行与重载 | 重复修改配置和重载、WAN 重连、断网恢复、检查 restart/OOM/内核日志。先观察 24 小时，再复测 6.18 NSS 的并发内存 |
| 边界与升级 | 从访客网和 WAN 验证 9527 不可达。同线保留升级后确认配置和管理员状态。跨线回退用对应原版并清空配置 |

Honk 对网关本机 IPv4 TCP 的兼容性及配置重载问题分别跟踪于 [#456](https://github.com/daeuniverse/honk/issues/456) 和 [#476](https://github.com/daeuniverse/honk/issues/476)。出现管理或 DNS 中断时先停止代理，根据 [安装与恢复指南](installation.md) 复核恢复路径。原版和 eBPF 版的镜像、校验值及 Release 各自独立。

## 构建来源

归档实现位于 [archive/honk-doona-20261116](https://github.com/osGex0o0II/ZN-M2-No-WIFI-Builder/tree/archive/honk-doona-20261116)。本版采用固定哈希的官方 ARM64 musl stock-full 资产。镜像中保留许可证与 Doona 声明，对应源码见 [NOTICE.md](../NOTICE.md)。发布前复制本次制造镜像的 Artifact、校验和与构建清单，供验收使用。
