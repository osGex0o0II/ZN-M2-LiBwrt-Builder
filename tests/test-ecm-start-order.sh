#!/bin/sh
# LEDE's qca-nss-ecm init registers at S19, before its S70 NSS driver, so ECM
# never loads on boot. The build must move it after the driver.
set -eu
repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"

grep -Fq 'ecm_init="$tree/feeds/nss_packages/qca-nss-ecm/files/qca-nss-ecm.init"' \
	"$repo_root/scripts/experimental-build.sh" || {
	echo "FAIL: experimental-build.sh does not patch the ECM init order" >&2
	exit 1
}
grep -Fq "sed -i 's/^START=19\$/START=99/'" "$repo_root/scripts/experimental-build.sh" || {
	echo "FAIL: the ECM init order rewrite is missing" >&2
	exit 1
}
if grep -Fq 'S99qca-nss-ecm' "$repo_root/files/etc/uci-defaults/97-zn-m2-ecm-enable.sh"; then
	echo "FAIL: uci-defaults must not relink ECM; rcS has already scanned rc.d" >&2
	exit 1
fi

echo "ecm start order regression test passed"
