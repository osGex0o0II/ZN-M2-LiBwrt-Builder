#!/usr/bin/env bash
# Emit the Chinese release notes for one ZN-M2 256M build line.
#
# Usage: release-notes.sh PROFILE [ASSETS_DIR]
#   PROFILE     profile id as declared in profiles/*.conf
#   ASSETS_DIR  optional directory holding the published images. When given,
#               the SHA256 of both images is embedded in the notes, so the
#               release does not need a separate SHA256SUMS asset.
#
# When the images are not available locally, set FACTORY_NAME, FACTORY_SHA256,
# SYSUPGRADE_NAME and SYSUPGRADE_SHA256 instead; for example when rewriting the
# notes of an already published release from the API asset digests.
set -euo pipefail

profile=${1:?usage: release-notes.sh PROFILE [ASSETS_DIR]}
assets=${2:-}

fail() { echo "release-notes: $*" >&2; exit 1; }

notes_header() {
	local title=$1 kernel=$2 acceleration=$3 positioning=$4
	cat <<EOF
## ${title} 固件

${positioning}

### 硬件与系统

- 机型：ZN-M2 256M 有线版（无 USB 接口，未编入 Wi-Fi 与 USB 驱动）
- 内核：${kernel}
- 转发加速：${acceleration}
- 内存：约 195 MiB 可用，另配 ZRAM 压缩，缓解 256M 内存压力
EOF
}

notes_defaults() {
	local password=$1 origin=$2
	cat <<EOF

### 默认设置

| 项目 | 默认值 |
|:---|:---|
| 管理地址 | \`192.168.1.1\` |
| 用户名 | \`root\` |
| 密码 | ${password} |
EOF
	if [ "$origin" = tuned ]; then
		cat <<'EOF'
| 主机名 | `ZN-M2` |
| DHCP 地址池 | `192.168.1.100`–`192.168.1.249` |
EOF
	fi
	cat <<'EOF'

- WAN 口接光猫或上级路由，LAN 口接内网设备。
- 首次登录后请立即设置或修改 root 密码；未设置密码时 SSH 不接受空密码登录。
- 保留配置升级会沿用原有地址与密码，管理地址不一定仍是 `192.168.1.1`。
EOF
	if [ "$origin" != tuned ]; then
		cat <<'EOF'
- 主机名、DHCP 地址池等未列出的项以上游默认值为准。
EOF
	fi
}

notes_plugins() {
	local proxy=$1 extras=$2
	cat <<EOF

### 主要插件

- 代理：${proxy}
- 集客 AC：\`gecoosac\`（已安装，服务默认停用）
- 网络工具：UPnP、ZeroTier、网络唤醒（均已安装，功能默认关闭）
- 运维：ttyd 网页终端（默认不自启）、定时重启
- 主题：Aurora，界面默认简体中文
${extras}
EOF
}

notes_tuning_official() {
	cat <<'EOF'

### 已做优化

- **转发加速**：直连流量走硬件加速，代理流量由 CPU 处理，互不干扰。
- **零重启首启**：开机先写入 LAN 的 DHCP 地址段再启动网络服务，首次启动即可拿到地址。
- **运行加固**：健康检查每 10 分钟确认 DHCP、默认路由、DNS、代理进程与可用内存，仅在需要时重启 dnsmasq 或 homeproxy，不整机重启。
- **内存**：未使用的无线子系统保留区缩减至 16 MiB，ZRAM 使用 lzo-rle，约 96 MiB。
- **网络**：拥塞控制 BBR + fq，TCP 缓冲区上限 2 MiB；DNS 缓存 8192 条、并发转发上限 300；conntrack 上限 16384。
- **可观测**：系统与内核日志缓冲各 256 KiB；首次启动自动运行 CoreMark，结果显示在 LuCI 概览页。
EOF
}

notes_tuning_adapted() {
	cat <<'EOF'

### 已做优化

- **256M 内存适配**：移除无线与 USB 相关驱动和固件，Q6 保留区缩减至 16 MiB，释放更多可用内存。
- **转发加速**：直连流量走硬件加速，代理流量由 CPU 处理。
- **上游原生**：运行时调优、默认插件与脚本以上游为准，本仓库仅做板级适配与构建验证。
EOF
}

notes_tail() {
	local howto=$1
	cat <<EOF

### 升级与刷机

- 首次刷入：通过 U-Boot 网页上传 \`*-factory.ubi\`。
- 已运行 OpenWrt：使用 \`sysupgrade -n\` 或 LuCI 上传 \`*-sysupgrade.bin\`。
- 跨内核或跨版本切换时不要保留配置；同一版本内升级可以保留。
- ${howto}
- 完整刷机步骤、救砖方式与常见问题见 [README](https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/blob/main/README.md)。

### 文件校验（SHA256）

下载后可用下表核对完整性，Windows 可执行 \`certutil -hashfile <文件> SHA256\`。
EOF
}

checksums_given() {
	local factory_name=$1 factory_sha=$2 sysupgrade_name=$3 sysupgrade_sha=$4
	[ -n "$factory_name" ] && [ -n "$factory_sha" ] &&
		[ -n "$sysupgrade_name" ] && [ -n "$sysupgrade_sha" ] ||
		fail "incomplete digest override for the published images"
	echo
	echo '| 文件 | 用途 | SHA256 |'
	echo '|:---|:---|:---|'
	printf '| `%s` | 首次通过 U-Boot 刷入 | `%s` |\n' "$factory_name" "$factory_sha"
	printf '| `%s` | 已运行 OpenWrt 时升级 | `%s` |\n' "$sysupgrade_name" "$sysupgrade_sha"
}

checksums() {
	local dir=$1
	[ -d "$dir" ] || fail "assets directory not found: $dir"
	local -a factories upgrades
	mapfile -t factories < <(find "$dir" -maxdepth 1 -type f -name '*-factory.ubi' | sort)
	mapfile -t upgrades < <(find "$dir" -maxdepth 1 -type f -name '*-sysupgrade.bin' | sort)
	[ "${#factories[@]}" -eq 1 ] || fail "expected one factory image in $dir, found ${#factories[@]}"
	[ "${#upgrades[@]}" -eq 1 ] || fail "expected one sysupgrade image in $dir, found ${#upgrades[@]}"
	echo
	echo '| 文件 | 用途 | SHA256 |'
	echo '|:---|:---|:---|'
	printf '| `%s` | 首次通过 U-Boot 刷入 | `%s` |\n' \
		"$(basename "${factories[0]}")" "$(sha256sum "${factories[0]}" | awk '{print $1}')"
	printf '| `%s` | 已运行 OpenWrt 时升级 | `%s` |\n' \
		"$(basename "${upgrades[0]}")" "$(sha256sum "${upgrades[0]}" | awk '{print $1}')"
}

case "$profile" in
libwrt-25.12-nss)
	notes_header "ZN-M2 LiBwrt 6.12 NSS" "6.12" "NSS + ECM（Qualcomm 硬件加速）" \
		"基于 LiBwrt 25.12，稳定性优先，适合长期作为主路由使用。"
	notes_defaults "首次登录时设置" tuned
	notes_plugins "HomeProxy + sing-box（已安装，未配置节点时不产生代理流量）" ""
	notes_tuning_official
	notes_tail "6.12 NSS 默认已关闭软件流量分载，不要与 NSS 同时开启。"
	;;
immortalwrt-viking-owrt-ppe)
	notes_header "ZN-M2 ImmortalWrt 6.18 PPE" "6.18" "qca-ppe + qca-edma（不使用 NSS）" \
		"基于 ImmortalWrt 6.18，内核较新，使用 PPE/EDMA 硬件分载。"
	notes_defaults "首次登录时设置" tuned
	notes_plugins "HomeProxy + sing-box（已安装，未配置节点时不产生代理流量）" ""
	notes_tuning_official
	cat <<'EOF'

### 实测参考

- PC 经 NAT 4 路并发约 300 Mbps 时，设备 CPU 占用约 0.1%（关闭分载时约 8.3%）。
- 镜像连续运行超过 31 小时，无 OOM、panic 或看门狗复位。
- 开关分载两种状态使用同一镜像区间，SHA256 一致。
EOF
	notes_tail "6.18 PPE 已卸载的连接会绕过 netfilter，按连接限速或计数类规则对其不生效；需要逐连接管控时请关闭流量分载。"
	;;
immortalwrt-viking-main-nss)
	notes_header "ZN-M2 ImmortalWrt 6.18 NSS" "6.18" "NSS + ECM（Qualcomm 硬件加速）" \
		"基于 ImmortalWrt main，较新内核与 NSS 兼得，内存占用高于 6.12 版本。"
	notes_defaults "首次登录时设置" upstream
	notes_plugins "HomeProxy + sing-box（已安装，未配置节点时不产生代理流量）" ""
	notes_tuning_adapted
	notes_tail "NSS 与软件流量分载不要同时开启；跨内核升级请勿保留配置。"
	;;
lede-master-nss)
	# LEDE decides its own kernel: upstream flipped qualcommax from 6.12 to
	# 6.18 on 2026-11-01 and may do it again. Report whatever the artifact name
	# carries instead of a hardcoded version, and fall back to a neutral phrase
	# when the notes are generated from the API digests rather than the files.
	lede_kernel=$(printf '%s' "${FACTORY_NAME:-}" | sed -n 's/.*-lede-master-nss-\([0-9][0-9.]*\)-.*/\1/p')
	notes_header "ZN-M2 LEDE 6.18 NSS" "${lede_kernel:-以 LEDE master 当前默认内核为准}" \
		"NSS + ECM（Qualcomm 硬件加速）" \
		"基于 LEDE master，保留上游默认风格，适合熟悉 LEDE 的用户。"
	notes_defaults "\`root\` / \`password\`（登录后请立即修改）" upstream
	notes_plugins "HomeProxy + sing-box（已安装，未配置节点时不产生代理流量）" ""
	notes_tuning_adapted
	notes_tail "LEDE 默认密码为公开值，刷入后请第一时间修改。"
	;;
fanchmwrt-25.12)
	notes_header "ZN-M2 FanchmWrt 6.12 FWX" "6.12" "FWX / Shortcut-FE（软件快速转发）" \
		"基于 FanchmWrt，接近上游原样，由上游维护板级支持与默认配置。"
	notes_defaults "以上游默认值为准，登录后请立即设置" upstream
	notes_plugins "以上游默认包集为准" "- 主题与默认服务由 FanchmWrt 上游决定。"
	notes_tuning_adapted
	notes_tail "默认密码、管理地址与插件以上游为准，刷机前请先阅读上游说明。"
	;;
*)
	fail "unknown profile: $profile"
	;;
esac

if [ -n "${FACTORY_SHA256:-}" ] || [ -n "${SYSUPGRADE_SHA256:-}" ]; then
	checksums_given "${FACTORY_NAME:-}" "${FACTORY_SHA256:-}" \
		"${SYSUPGRADE_NAME:-}" "${SYSUPGRADE_SHA256:-}"
	echo
	echo "本次发布仅提供上述两个镜像文件，校验值已写入本说明。"
elif [ -n "$assets" ]; then
	checksums "$assets"
	echo
	echo "本次发布仅提供上述两个镜像文件，校验值已写入本说明。"
fi
