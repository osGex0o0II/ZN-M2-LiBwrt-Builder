#!/bin/sh
# LEDE's qca-nss-ecm init registers at S19, before its S70 NSS driver, so ECM
# never loads on boot. The build must move it after the driver, and it must
# find the feed that actually carries the package instead of assuming a name.
set -eu
repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
build_script="$repo_root/scripts/experimental-build.sh"

grep -Fq 'for ecm_init in "$tree"/feeds/*/qca-nss-ecm/files/qca-nss-ecm.init' \
	"$build_script" || {
	echo "FAIL: experimental-build.sh does not discover the ECM init script" >&2
	exit 1
}
grep -Fq "sed -i 's/^START=[0-9][0-9]*\$/START=99/'" "$build_script" || {
	echo "FAIL: the ECM init order rewrite is missing" >&2
	exit 1
}
grep -Fq 'qca-nss-ecm init script not found under' "$build_script" || {
	echo "FAIL: a missing ECM init script must fail the prepare step" >&2
	exit 1
}
grep -Fq '[ "$PROFILE_ID" = "lede-master-nss" ]' "$build_script" || {
	echo "FAIL: the ECM start-order rewrite must not touch other profiles" >&2
	exit 1
}
if grep -Fq 'S99qca-nss-ecm' "$repo_root/files/etc/uci-defaults/97-zn-m2-ecm-enable.sh"; then
	echo "FAIL: uci-defaults must not relink ECM; rcS has already scanned rc.d" >&2
	exit 1
fi

# The discovery must work for any feed directory name.
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT HUP INT TERM
mkdir -p "$workdir/feeds/some_feed/qca-nss-ecm/files"
printf '#!/bin/sh\nSTART=19\n' > "$workdir/feeds/some_feed/qca-nss-ecm/files/qca-nss-ecm.init"
for ecm_init in "$workdir"/feeds/*/qca-nss-ecm/files/qca-nss-ecm.init; do
	[ -f "$ecm_init" ] || continue
	grep -q '^START=[0-9][0-9]*$' "$ecm_init" || continue
	sed -i 's/^START=[0-9][0-9]*$/START=99/' "$ecm_init"
done
grep -Fxq 'START=99' "$workdir/feeds/some_feed/qca-nss-ecm/files/qca-nss-ecm.init" || {
	echo "FAIL: discovery did not rewrite a non-nss_packages feed" >&2
	exit 1
}

echo "ecm start order regression test passed"
