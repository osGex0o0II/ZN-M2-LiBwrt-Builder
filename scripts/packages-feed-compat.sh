#!/bin/sh

# Shared packages-feed compatibility classification and repair functions.

packages_feed_freeradius_state() {
	local makefile="$1"
	local dependency_pair
	local server_block
	local common_block
	local utils_block

	if [ ! -f "$makefile" ]; then
		printf '%s\n' invalid
		return 0
	fi

	dependency_pair='+FREERADIUS3_OPENSSL:libopenssl +FREERADIUS3_OPENSSL:libopenssl-legacy'
	server_block="$(sed -n '/^define Package\/freeradius3$/,/^endef$/p' "$makefile")"
	common_block="$(sed -n '/^define Package\/freeradius3-common$/,/^endef$/p' "$makefile")"
	utils_block="$(sed -n '/^define Package\/freeradius3-utils$/,/^endef$/p' "$makefile")"

	if printf '%s\n' "$server_block" |
		grep -Eq '^[[:space:]]*DEPENDS:=\+freeradius3-common \+FREERADIUS3_OPENSSL:libopenssl \+FREERADIUS3_OPENSSL:libopenssl-legacy[[:space:]]*$' &&
	   ! printf '%s\n' "$server_block" |
		grep -Eq '^[[:space:]]*DEPENDS:=\+freeradius3-common[[:space:]]*$' &&
	   printf '%s\n' "$common_block" |
		grep -Eq '^[[:space:]]*DEPENDS:=[^#]*\+FREERADIUS3_OPENSSL:libopenssl \+FREERADIUS3_OPENSSL:libopenssl-legacy' &&
	   printf '%s\n' "$utils_block" |
		grep -Eq '^[[:space:]]*DEPENDS:=\+freeradius3-common \+FREERADIUS3_OPENSSL:libopenssl \+FREERADIUS3_OPENSSL:libopenssl-legacy[[:space:]]*$' &&
	   ! printf '%s\n' "$utils_block" |
		grep -Eq '^[[:space:]]*DEPENDS:=\+freeradius3-common[[:space:]]*$'; then
		printf '%s\n' modern-fixed
		return 0
	fi

	if grep -Fxq 'PKG_VERSION:=3.2.8' "$makefile" &&
	   printf '%s\n' "$server_block" |
		grep -Eq '^[[:space:]]*DEPENDS:=\+freeradius3-common[[:space:]]*$' &&
	   printf '%s\n' "$common_block" |
		grep -Eq '^[[:space:]]*DEPENDS:=[^#]*\+FREERADIUS3_OPENSSL:libopenssl \+libcap' &&
	   printf '%s\n' "$utils_block" |
		grep -Eq '^[[:space:]]*DEPENDS:=\+freeradius3-common[[:space:]]*$' &&
	   ! grep -Fq 'libopenssl-legacy' "$makefile"; then
		printf '%s\n' legacy-safe
		return 0
	fi

	printf '%s\n' invalid
}

packages_feed_trafficshaper_state() {
	local makefile="$1"
	local default_block
	local nftables_block
	local iptables_block

	if [ ! -f "$makefile" ]; then
		printf '%s\n' invalid
		return 0
	fi

	default_block="$(sed -n '/^define Package\/trafficshaper\/Default$/,/^endef$/p' "$makefile")"
	nftables_block="$(sed -n '/^define Package\/trafficshaper$/,/^endef$/p' "$makefile")"
	iptables_block="$(sed -n '/^define Package\/trafficshaper-iptables$/,/^endef$/p' "$makefile")"

	if printf '%s\n' "$default_block" |
		grep -Eq '^[[:space:]]*PROVIDES:=trafficshaper[[:space:]]*$' &&
	   printf '%s\n' "$nftables_block" |
		grep -Eq '^[[:space:]]*DEPENDS\+= \+nftables[[:space:]]*$' &&
	   printf '%s\n' "$nftables_block" |
		grep -Eq '^[[:space:]]*VARIANT:=nftables[[:space:]]*$' &&
	   printf '%s\n' "$nftables_block" |
		grep -Eq '^[[:space:]]*DEFAULT_VARIANT:=1[[:space:]]*$' &&
	   printf '%s\n' "$nftables_block" |
		grep -Eq '^[[:space:]]*\$\(call Package/trafficshaper/Default\)[[:space:]]*$' &&
	   printf '%s\n' "$iptables_block" |
		grep -Eq '^[[:space:]]*DEPENDS\+= \+iptables \+IPV6:ip6tables \+iptables-mod-conntrack-extra[[:space:]]*$' &&
	   printf '%s\n' "$iptables_block" |
		grep -Eq '^[[:space:]]*VARIANT:=iptables[[:space:]]*$' &&
	   printf '%s\n' "$iptables_block" |
		grep -Eq '^[[:space:]]*\$\(call Package/trafficshaper/Default\)[[:space:]]*$' &&
	   printf '%s\n' "$iptables_block" |
		grep -Eq '^[[:space:]]*CONFLICTS:=trafficshaper[[:space:]]*$' &&
	   grep -Eq '^[[:space:]]*\$\(eval \$\(call BuildPackage,trafficshaper\)\)[[:space:]]*$' "$makefile" &&
	   grep -Eq '^[[:space:]]*\$\(eval \$\(call BuildPackage,trafficshaper-iptables\)\)[[:space:]]*$' "$makefile" &&
	   ! grep -Fq 'PACKAGE_nftables-' "$makefile"; then
		printf '%s\n' modern-fixed
		return 0
	fi

	if grep -Fxq 'PKG_RELEASE:=3' "$makefile" &&
	   printf '%s\n' "$nftables_block" |
		grep -Eq '^[[:space:]]*DEPENDS:=.*\+iptables \+IPV6:ip6tables' &&
	   ! grep -Fq 'nftables' "$makefile" &&
	   ! grep -Fq 'Package/trafficshaper/Default' "$makefile" &&
	   ! grep -Fq 'Package/trafficshaper-iptables' "$makefile"; then
		printf '%s\n' legacy-safe
		return 0
	fi

	printf '%s\n' invalid
}

packages_feed_patch_state() {
	local feed_dir="$1"
	local patch_file="$2"

	case "$(basename "$patch_file")" in
	freeradius3-kconfig-recursive-dependency.patch)
		packages_feed_freeradius_state \
			"$feed_dir/net/freeradius3/Makefile"
		;;
	trafficshaper-kconfig-recursive-dependency.patch)
		packages_feed_trafficshaper_state \
			"$feed_dir/net/trafficshaper/Makefile"
		;;
	*)
		printf '%s\n' invalid
		;;
	esac
}

packages_feed_repair_one() {
	local feed_dir="$1"
	local patch_file="$2"
	local patch_name
	local state
	local final_state

	patch_name="$(basename "$patch_file")"
	case "$patch_name" in
	freeradius3-kconfig-recursive-dependency.patch|trafficshaper-kconfig-recursive-dependency.patch)
		;;
	*)
		echo "ERROR: Unsupported packages feed compatibility patch: ${patch_file}" >&2
		return 1
		;;
	esac

	state="$(packages_feed_patch_state "$feed_dir" "$patch_file")"
	case "$state" in
	modern-fixed)
		if git -C "$feed_dir" apply --reverse --check "$patch_file" 2>/dev/null; then
			echo "Packages feed compatibility patch already applied, skip: ${patch_name}"
		else
			echo "Packages feed already contains compatible repair, skip: ${patch_name}"
		fi
		;;
	legacy-safe)
		echo "Known pre-regression packages feed, compatibility patch not needed: ${patch_name}"
		;;
	invalid)
		if ! git -C "$feed_dir" apply --check "$patch_file" 2>/dev/null; then
			echo "ERROR: Packages feed target is invalid and patch does not apply: ${patch_file}" >&2
			return 1
		fi
		git -C "$feed_dir" apply "$patch_file"
		echo "Applied packages feed compatibility patch: ${patch_name}"
		;;
	esac

	final_state="$(packages_feed_patch_state "$feed_dir" "$patch_file")"
	case "$final_state" in
	modern-fixed|legacy-safe)
		return 0
		;;
	*)
		echo "ERROR: Packages feed target remains invalid after compatibility handling: ${patch_name}" >&2
		return 1
		;;
	esac
}

packages_feed_repair() {
	local feed_dir="$1"
	local patch_dir="$2"
	local feed_path
	local git_top
	local makefile
	local patch_file

	feed_path="$(CDPATH='' cd -- "$feed_dir" 2>/dev/null && pwd -P)" || {
		echo "ERROR: Pinned packages feed directory is missing: ${feed_dir}" >&2
		return 1
	}
	if [ ! -e "$feed_path/.git" ]; then
		echo "ERROR: Pinned packages feed git worktree is missing: ${feed_dir}" >&2
		return 1
	fi
	git_top="$(git -C "$feed_path" rev-parse --show-toplevel 2>/dev/null || true)"
	git_top="$(CDPATH='' cd -- "$git_top" 2>/dev/null && pwd -P)" || true
	if [ -z "$git_top" ] || [ "$git_top" != "$feed_path" ]; then
		echo "ERROR: Pinned packages feed git worktree is missing: ${feed_dir}" >&2
		return 1
	fi

	for makefile in \
		"$feed_dir/net/freeradius3/Makefile" \
		"$feed_dir/net/trafficshaper/Makefile"; do
		if [ ! -f "$makefile" ]; then
			echo "ERROR: Missing packages feed Makefile: ${makefile}" >&2
			return 1
		fi
	done

	for patch_file in \
		"$patch_dir/freeradius3-kconfig-recursive-dependency.patch" \
		"$patch_dir/trafficshaper-kconfig-recursive-dependency.patch"; do
		if [ ! -f "$patch_file" ]; then
			echo "ERROR: Missing packages feed compatibility patch: ${patch_file}" >&2
			return 1
		fi
		packages_feed_repair_one "$feed_dir" "$patch_file" || return 1
	done
}
