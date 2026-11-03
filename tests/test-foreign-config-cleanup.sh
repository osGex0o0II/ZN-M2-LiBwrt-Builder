#!/bin/sh
# Cross-distro flashes keep configuration for packages the image does not
# install. The shared cleanup removes those orphans (and ssr-plus resolver
# fragments) while leaving installed packages untouched.
set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cleanup="$repo_root/files-shared/etc/uci-defaults/96-clean-foreign-config.sh"
[ -f "$cleanup" ] || {
	echo "FAIL: missing $cleanup" >&2
	exit 1
}

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT HUP INT TERM
mkdir -p "$workdir/config" "$workdir/init.d" "$workdir/dnsmasq.d/dnsmasq-ssrplus.d"

for stale in 3proxy shadowsocksr vlmcsd vsftpd microsocks nlbwmon oui arpbind appfilter; do
	: > "$workdir/config/$stale"
done
# 3proxy is still installed, so its configuration must survive.
cat > "$workdir/init.d/3proxy" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$workdir/init.d/3proxy"

printf '%s\n' 'server=1.1.1.1' > "$workdir/dnsmasq.d/dnsmasq-ssrplus.conf"
printf '%s\n' 'address=/example/1.2.3.4' > "$workdir/dnsmasq.d/dnsmasq-ssrplus.d/orphan.conf"

ZN_M2_CONFIG_DIR="$workdir/config" \
ZN_M2_INIT_DIR="$workdir/init.d" \
ZN_M2_DNSMASQ_D="$workdir/dnsmasq.d" \
	sh "$cleanup"

[ -e "$workdir/config/3proxy" ] || {
	echo "FAIL: config for an installed package was removed" >&2
	exit 1
}
for stale in shadowsocksr vlmcsd vsftpd microsocks nlbwmon oui arpbind appfilter; do
	[ ! -e "$workdir/config/$stale" ] || {
		echo "FAIL: stale config $stale was kept" >&2
		exit 1
	}
done
[ ! -e "$workdir/dnsmasq.d/dnsmasq-ssrplus.conf" ] || {
	echo "FAIL: ssr-plus dnsmasq drop-in was kept" >&2
	exit 1
}
[ ! -d "$workdir/dnsmasq.d/dnsmasq-ssrplus.d" ] || {
	echo "FAIL: ssr-plus dnsmasq directory was kept" >&2
	exit 1
}

# The fragments stay when the package is still installed.
printf '%s\n' 'server=1.1.1.1' > "$workdir/dnsmasq.d/dnsmasq-ssrplus.conf"
cat > "$workdir/init.d/shadowsocksr" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$workdir/init.d/shadowsocksr"
ZN_M2_CONFIG_DIR="$workdir/config" \
ZN_M2_INIT_DIR="$workdir/init.d" \
ZN_M2_DNSMASQ_D="$workdir/dnsmasq.d" \
	sh "$cleanup"
[ -e "$workdir/dnsmasq.d/dnsmasq-ssrplus.conf" ] || {
	echo "FAIL: ssr-plus drop-in was removed while the package is installed" >&2
	exit 1
}

# Both staging policies must receive the shared overlay.
grep -Fq 'files-shared' "$repo_root/scripts/experimental-build.sh" || {
	echo "FAIL: files-shared is not staged" >&2
	exit 1
}

echo "foreign config cleanup regression test passed"
