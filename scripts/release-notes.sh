#!/usr/bin/env bash
# Emit the Chinese release notes for one ZN-M2 256M build line.
#
# Usage: release-notes.sh PROFILE [ASSETS_DIR] [BUILD_MANIFEST]
#   PROFILE         profile id as declared in profiles/*.conf
#   ASSETS_DIR      optional directory holding the published images. When given,
#                   the SHA256 of both images is embedded in the notes, so the
#                   release does not need a separate SHA256SUMS asset.
#   BUILD_MANIFEST  optional BUILD-MANIFEST.txt. When given, the shared
#                   source/build provenance block is appended to the notes.
#
# When the images are not available locally, set FACTORY_NAME, FACTORY_SHA256,
# SYSUPGRADE_NAME and SYSUPGRADE_SHA256 instead; for example when rewriting the
# notes of an already published release from the API asset digests.
set -euo pipefail

profile=${1:?usage: release-notes.sh PROFILE [ASSETS_DIR] [BUILD_MANIFEST]}
assets=${2:-}
manifest=${3:-}

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
- 物理内存：256 MB；系统可见内存受内核及加速栈保留区影响
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
- 首次登录后请立即确认 root 密码与远程管理策略。
- 保留配置升级会沿用原有地址与密码，管理地址不一定仍是 `192.168.1.1`。
EOF
	if [ "$origin" != tuned ]; then
		cat <<'EOF'
- 主机名、DHCP 地址池等未列出的项以上游默认值为准。
EOF
	fi
}

notes_plugins() {
	# Do not advertise the other profiles' packages for FanchmWrt.
	if [ "$profile" = "fanchmwrt-25.12" ]; then
		cat <<'EOF'

### 软件与服务

- 保留 FanchmWrt 上游的主题、插件与服务配置。
- 首次启动会尝试启用 fastnat；其他加速与服务设置以上游为准。
- 插件清单以本次 FanchmWrt 构建和上游配置为准。
EOF
		return
	fi
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

- **转发加速**：符合条件的直连连接可使用硬件分载；代理处理通常需要 CPU 参与。
- **DHCP 预置**：在初始启动阶段设置 LAN DHCP 地址段，减少服务启动顺序导致的分配问题。
- **运行加固**：健康检查每 10 分钟确认 DHCP、默认路由、DNS、代理进程与可用内存，仅在需要时重启 dnsmasq 或 homeproxy，不整机重启。
- **内存**：未使用的无线子系统保留区缩减至 16 MiB，ZRAM 使用 lzo-rle，约 96 MiB。
- **网络**：拥塞控制 BBR + fq，TCP 缓冲区上限 2 MiB；DNS 缓存 8192 条、并发转发上限 300；conntrack 上限 16384。
- **可观测**：系统与内核日志缓冲各 256 KiB；首次启动自动运行 CoreMark，结果显示在 LuCI 概览页。
EOF
}

notes_tuning_adapted() {
	if [ "$profile" = "fanchmwrt-25.12" ]; then
		cat <<'EOF'

### 构建特性

- 保留 FanchmWrt 原生界面与 FWX / Shortcut-FE 快速转发体系。
- 修正 ZN-M2 LAN 端口标签及 LuCI 状态面板显示顺序。
- 不沿用其他构建线的默认服务和运行时调优。
EOF
		return
	fi
	cat <<'EOF'

### 已做优化

- **256M 内存适配**：移除无线与 USB 相关驱动和固件，Q6 保留区缩减至 16 MiB，释放更多可用内存。
- **转发加速**：符合条件的直连连接可使用 NSS；代理处理通常需要 CPU 参与。
- **上游适配**：保留 NSS 所需内存区域，并按此构建线配置板级文件与软件包。
EOF
}

notes_tail() {
	local howto=$1
	cat <<EOF

### 升级与刷机

- 首次刷机：仅在兼容的 U-Boot 刷机环境中使用 \`*-factory.ubi\`，不能直接当作原厂升级包。
- 已运行兼容的 OpenWrt 系固件：使用 LuCI 或 \`sysupgrade\` 安装 \`*-sysupgrade.bin\`。
- 跨构建线或跨内核切换时不保留配置；同线升级前也应备份并阅读发布说明。
- ${howto}
- 安装与恢复注意事项见 [安装指南](https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder/blob/main/docs/installation.md)。

### 文件校验（SHA256）

下载后按下表核对完整性。Windows 示例：\`certutil -hashfile "实际文件名.bin" SHA256\`。
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

notes_provenance() {
	local manifest=$1 source branch source_commit kernel builder run source_display
	[ -f "$manifest" ] || fail "build manifest not found: $manifest"
	field() {
		awk -v key="$1" '
			index($0, key ":") == 1 {
				value = substr($0, length(key) + 2)
				sub(/^[[:space:]]*/, "", value)
				print value
				exit
			}
		' "$manifest"
	}
	source=$(field 'Source repository')
	branch=$(field 'Source branch')
	source_commit=$(field 'Source commit')
	kernel=$(field 'Kernel')
	builder=$(field 'Builder commit')
	run=$(field 'Run')
	[ -n "$source$branch$source_commit$kernel$builder$run" ] || return 0
	if [ -n "$source" ]; then
		source_display="[${source}](${source})（分支 ${branch:-未知}）"
	else
		source_display="未知"
	fi
	cat <<EOF

### 源码与构建信息

- 源码：${source_display}
- 内核：${kernel:-未知}
- 源码提交：${source_commit:-未知}
- 构建提交：${builder:-未知}
- 构建运行：${run:-未知}
EOF
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
		"基于 LiBwrt 25.12 的 ZN-M2 有线固件，采用 NSS + ECM。"
	notes_defaults "首次登录时设置" tuned
	notes_plugins "HomeProxy + sing-box（已安装，未配置节点时不产生代理流量）" ""
	notes_tuning_official
	notes_tail "6.12 NSS 默认已关闭软件流量分载，不要与 NSS 同时开启。"
	;;
immortalwrt-viking-owrt-ppe)
	notes_header "ZN-M2 ImmortalWrt 6.18 PPE" "6.18" "qca-ppe + qca-edma（不使用 NSS）" \
		"基于 VIKINGYFY owrt 的 ZN-M2 有线固件，采用 PPE + EDMA。"
	notes_defaults "首次登录时设置" tuned
	notes_plugins "HomeProxy + sing-box（已安装，未配置节点时不产生代理流量）" ""
	notes_tuning_official
	cat <<'EOF'

### 历史测试记录

- PC 经 NAT 4 路并发约 300 Mbps 时，设备 CPU 占用约 0.1%（关闭分载时约 8.3%）。
- 镜像连续运行超过 31 小时，无 OOM、panic 或看门狗复位。
- 上述数据来自特定设备与测试环境，不能直接推导代理性能。
EOF
	notes_tail "PPE 硬件分载可能影响逐包限速、计数与部分防火墙扩展规则，需在实际流量中验证。"
	;;
immortalwrt-viking-main-nss)
	notes_header "ZN-M2 ImmortalWrt 6.18 NSS" "6.18" "NSS + ECM（Qualcomm 硬件加速）" \
		"基于 VIKINGYFY main 的 ZN-M2 有线固件，采用 NSS + ECM。"
	notes_defaults "首次登录时设置" upstream
	notes_plugins "HomeProxy + sing-box（已安装，未配置节点时不产生代理流量）" ""
	notes_tuning_adapted
	notes_tail "NSS 与软件流量分载不要同时开启；跨内核升级请勿保留配置。"
	;;
fanchmwrt-25.12)
	notes_header "ZN-M2 FanchmWrt 6.12 FWX" "6.12" "FWX / Shortcut-FE（软件快速转发）" \
		"基于 FanchmWrt 的 ZN-M2 有线固件，保留其原生软件栈。"
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

if [ -n "$manifest" ]; then
	notes_provenance "$manifest"
fi
