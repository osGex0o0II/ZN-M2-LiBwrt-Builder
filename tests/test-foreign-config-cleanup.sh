#!/bin/sh
# Cross-distro flashes keep configuration for packages the image does not
# install. The shared cleanup removes those orphans (and ssr-plus resolver
# fragments) while leaving installed packages untouched, including packages
# that have no init script.
set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cleanup="$repo_root/files-shared/etc/uci-defaults/96-clean-foreign-config.sh"
[ -f "$cleanup" ] || {
	echo "FAIL: missing $cleanup" >&2
	exit 1
}

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT HUP INT TERM
mkdir -p "$workdir/bin" "$workdir/config" "$workdir/init.d" "$workdir/dnsmasq.d/dnsmasq-ssrplus.d"

# apk stub: only 3proxy and luci-app-oui are installed. oui has no init script,
# so the package-name guard is the only thing keeping its config alive.
cat > "$workdir/bin/apk" <<'EOF'
#!/bin/sh
cat <<'LIST'
3proxy-0.9.4-r1 aarch64_cortex-a53 {feeds/packages/net/3proxy} (GPL-3.0-or-later)
luci-app-oui-1.2.3-r1 aarch64_cortex-a53 {feeds/luci/applications/luci-app-oui} (Apache-2.0)
LIST
EOF
chmod +x "$workdir/bin/apk"

for stale in 3proxy shadowsocksr vlmcsd vsftpd microsocks nlbwmon oui arpbind appfilter; do
	: > "$workdir/config/$stale"
done
cat > "$workdir/init.d/3proxy" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$workdir/init.d/3proxy"

printf '%s\n' 'server=1.1.1.1' > "$workdir/dnsmasq.d/dnsmasq-ssrplus.conf"
printf '%s\n' 'address=/example/1.2.3.4' > "$workdir/dnsmasq.d/dnsmasq-ssrplus.d/orphan.conf"

PATH="$workdir/bin:$PATH" \
ZN_M2_CONFIG_DIR="$workdir/config" \
ZN_M2_INIT_DIR="$workdir/init.d" \
ZN_M2_DNSMASQ_D="$workdir/dnsmasq.d" \
	sh "$cleanup"

for keep in 3proxy oui; do
	[ -e "$workdir/config/$keep" ] || {
		echo "FAIL: config for installed package $keep was removed" >&2
		exit 1
	}
done
for stale in shadowsocksr vlmcsd vsftpd microsocks nlbwmon arpbind appfilter; do
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

# The fragments stay when the package is still installed (config name differs
# from the package name here: shadowsocksr / shadowsocksr-libev).
printf '%s\n' 'server=1.1.1.1' > "$workdir/dnsmasq.d/dnsmasq-ssrplus.conf"
: > "$workdir/config/shadowsocksr"
cat > "$workdir/bin/apk" <<'EOF'
#!/bin/sh
cat <<'LIST'
3proxy-0.9.4-r1 aarch64_cortex-a53 {feeds/packages/net/3proxy} (GPL-3.0-or-later)
luci-app-oui-1.2.3-r1 aarch64_cortex-a53 {feeds/luci/applications/luci-app-oui} (Apache-2.0)
shadowsocksr-libev-3.2.5-r2 aarch64_cortex-a53 {feeds/packages/net/shadowsocksr-libev} (GPL-3.0)
LIST
EOF
chmod +x "$workdir/bin/apk"

PATH="$workdir/bin:$PATH" \
ZN_M2_CONFIG_DIR="$workdir/config" \
ZN_M2_INIT_DIR="$workdir/init.d" \
ZN_M2_DNSMASQ_D="$workdir/dnsmasq.d" \
	sh "$cleanup"
[ -e "$workdir/dnsmasq.d/dnsmasq-ssrplus.conf" ] || {
	echo "FAIL: ssr-plus drop-in was removed while the package is installed" >&2
	exit 1
}
[ -e "$workdir/config/shadowsocksr" ] || {
	echo "FAIL: shadowsocksr config was removed while the package is installed" >&2
	exit 1
}

# Both staging policies must receive the shared overlay.
grep -Fq 'files-shared' "$repo_root/scripts/experimental-build.sh" || {
	echo "FAIL: files-shared is not staged" >&2
	exit 1
}

echo "foreign config cleanup regression test passed"
