#!/bin/sh
# LEDE's qca-nss-ecm init registers at S19, before its S70 NSS driver, so ECM
# never loads on boot. The build must move it after the driver, and it must
# find the feed that actually carries the package instead of assuming a name.
set -eu
repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
build_script="$repo_root/scripts/experimental-build.sh"

grep -Fq 'for candidate in \' "$build_script" || {
	echo "FAIL: experimental-build.sh does not discover the ECM init script" >&2
	exit 1
}
grep -Fq '$tree"/package/*/qca-nss-ecm/files/qca-nss-ecm.init' "$build_script" || {
	echo "FAIL: the ECM discovery must also search vendored packages" >&2
	exit 1
}
grep -Fq "sed -i 's/^START=[0-9][0-9]*\$/START=99/'" "$build_script" || {
	echo "FAIL: the ECM init order rewrite is missing" >&2
	exit 1
}
grep -Fq 'qca-nss-ecm init script not found or has no START= under' "$build_script" || {
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

# Discovery must work for a feed directory and for both vendored layouts.
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT HUP INT TERM

patch_tree() {
	tree="$1"
	ecm_init=""
	for candidate in \
		"$tree"/feeds/*/qca-nss-ecm/files/qca-nss-ecm.init \
		"$tree"/package/*/qca-nss-ecm/files/qca-nss-ecm.init \
		"$tree"/package/*/*/qca-nss-ecm/files/qca-nss-ecm.init; do
		[ -f "$candidate" ] || continue
		ecm_init="$candidate"
		break
	done
	if [ -z "$ecm_init" ]; then
		ecm_init="$(find "$tree/feeds" "$tree/package" -maxdepth 5 \
			-path '*/qca-nss-ecm/files/qca-nss-ecm.init' 2>/dev/null | head -n 1)"
	fi
	[ -n "$ecm_init" ] || return 1
	grep -q '^START=[0-9][0-9]*$' "$ecm_init" || return 1
	sed -i 's/^START=[0-9][0-9]*$/START=99/' "$ecm_init"
}

case_index=0
for layout in \
	"feeds/some_feed/qca-nss-ecm/files" \
	"package/qca/qca-nss-ecm/files" \
	"package/vendor/qca-nss-ecm/files"; do
	case_index=$((case_index + 1))
	tree="$workdir/tree$case_index"
	mkdir -p "$tree/$layout"
	printf '#!/bin/sh\nSTART=19\n' > "$tree/$layout/qca-nss-ecm.init"
	patch_tree "$tree" || {
		echo "FAIL: discovery failed for $layout" >&2
		exit 1
	}
	grep -Fxq 'START=99' "$tree/$layout/qca-nss-ecm.init" || {
		echo "FAIL: discovery did not rewrite $layout" >&2
		exit 1
	}
done

echo "ecm start order regression test passed"
