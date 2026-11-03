#!/bin/sh
# Runtime defaults that must not silently regress:
# - FanchmWrt ships fastnat disabled; the profile enables it at first boot.
# - ttyd is a root web terminal and stays off unless the admin turns it on.
# - Cross-distro flashes must not leave foreign package configuration behind.
set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"

fanch="$repo_root/files-upstream-native/etc/uci-defaults/97-fanch-fastnat-default.sh"
ttyd="$repo_root/files/etc/uci-defaults/98-zn-m2-disable-ttyd.sh"
migration="$repo_root/files-zn-m2/etc/uci-defaults/96-upgrade-runtime-migration.sh"

for file in "$fanch" "$ttyd" "$migration"; do
	[ -f "$file" ] || {
		echo "FAIL: missing $file" >&2
		exit 1
	}
done

grep -Fq "fastnat.global.enabled='1'" "$fanch" || {
	echo "FAIL: FanchmWrt fastnat is not enabled by default" >&2
	exit 1
}
grep -Fq 'uci -q commit fastnat' "$fanch" || {
	echo "FAIL: fastnat default is not committed" >&2
	exit 1
}

grep -Fq "ttyd.@ttyd[0].enabled='0'" "$ttyd" || {
	echo "FAIL: ttyd is not disabled by default" >&2
	exit 1
}

# The upstream-native staging branch must copy the accelerator default.
grep -Fq 'files-upstream-native' "$repo_root/scripts/experimental-build.sh" || {
	echo "FAIL: files-upstream-native is not staged" >&2
	exit 1
}

# Stale cross-distro configuration cleanup and the one-time ttyd migration.
for marker in \
	'for stale in 3proxy shadowsocksr vlmcsd vsftpd microsocks nlbwmon oui arpbind appfilter' \
	'dnsmasq-ssrplus.conf' \
	'dnsmasq-ssrplus.d' \
	"ttyd.@ttyd[0].enabled='0'" \
	"zn-m2.settings.ttyd_default='1'"; do
	grep -Fq -- "$marker" "$migration" || {
		echo "FAIL: migration is missing: $marker" >&2
		exit 1
	}
done

echo "runtime default contract tests passed"
