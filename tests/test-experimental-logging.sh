#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
if [ -n "${TEST_ARTIFACT_DIR:-}" ]; then
  mkdir -p "$TEST_ARTIFACT_DIR"
  tmp=$(cd "$TEST_ARTIFACT_DIR" && pwd)
else
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
fi
fail() { echo "FAIL: $*" >&2; exit 1; }

run_build() {
  local scenario=$1 download_rc=$2 parallel_rc=$3 serial_rc=$4 expected=$5 rc=0
  local tree="$tmp/$scenario"
  mkdir -p "$tree"
  : > "$tree/stages"
  cat > "$tree/.config" <<'CONFIG'
CONFIG_TARGET_qualcommax_ipq60xx=y
CONFIG_TARGET_qualcommax_ipq60xx_DEVICE_zn_m2=y
CONFIG_TARGET_ROOTFS_SQUASHFS=y
CONFIG_PACKAGE_kmod-qca-nss-drv=y
CONFIG_PACKAGE_kmod-qca-nss-ecm=y
CONFIG_PACKAGE_luci-app-homeproxy=y
CONFIG_PACKAGE_sing-box=y
CONFIG_PACKAGE_luci-theme-aurora=y
CONFIG
  cat > "$tree/Makefile" <<'MAKEFILE'
.PHONY: all download
all:
ifeq ($(V),s)
	@echo serial >> stages; echo serial-stdout; echo serial-stderr >&2; exit $(SERIAL_RC)
else
	@echo parallel >> stages; echo parallel-stdout; echo parallel-stderr >&2; exit $(PARALLEL_RC)
endif
download:
	@echo download >> stages; echo download-stdout; echo download-stderr >&2; exit $(DOWNLOAD_RC)
MAKEFILE
  DOWNLOAD_RC=$download_rc PARALLEL_RC=$parallel_rc SERIAL_RC=$serial_rc \
    bash "$root/scripts/experimental-build.sh" build immortalwrt-viking-main-nss "$tree" > "$tree/console.log" 2>&1 || rc=$?
  [ "$rc" = "$expected" ] || fail "$scenario status: expected $expected, got $rc"
  grep -Fq download-stdout "$tree/build.log" || fail "$scenario missing download stdout"
  grep -Fq download-stderr "$tree/build.log" || fail "$scenario missing download stderr"
  printf 'PASS: %s exit=%s\n' "$scenario" "$rc"
}

run_build success 0 0 0 0
printf 'download\nparallel\n' > "$tmp/expected-stages"
diff -u "$tmp/expected-stages" "$tmp/success/stages"
grep -Fq 'parallel exit status: 0' "$tmp/success/build.log"
grep -Fq parallel-stderr "$tmp/success/build.log"

# GNU make returns 2 for a recipe failure, independently of the recipe's exit 7.
run_build download-failure 7 0 0 2
printf 'download\n' > "$tmp/expected-stages"
diff -u "$tmp/expected-stages" "$tmp/download-failure/stages"
run_build serial-recovery 0 7 0 0
run_build serial-failure 0 7 9 2
printf 'download\nparallel\nserial\n' > "$tmp/expected-stages"
for scenario in serial-recovery serial-failure; do
  diff -u "$tmp/expected-stages" "$tmp/$scenario/stages"
  grep -Fq 'parallel exit status: 2' "$tmp/$scenario/build.log"
  grep -Fq serial-stdout "$tmp/$scenario/build.log"
  grep -Fq serial-stderr "$tmp/$scenario/build.log"
done

# Exercise the production logging helper with a non-make failure code.
rc=0
bash -c 'source "$1/scripts/experimental-build.sh"; run_logged_command "$2" bash -c "echo command-stdout; echo command-stderr >&2; exit 7"' \
  _ "$root" "$tmp/command.log" > "$tmp/command-console.log" 2>&1 || rc=$?
[ "$rc" = 7 ] || fail "logged command expected exit 7, got $rc"
grep -Fxq command-stdout "$tmp/command.log"
grep -Fxq command-stderr "$tmp/command.log"
echo 'PASS: logged command exit=7, stdout and stderr captured'
echo 'experimental logging tests passed'
