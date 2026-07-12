#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
WF_1G="$ROOT_DIR/.github/workflows/zn-m2-1g-proxy-gateway.yml"
WF_256="$ROOT_DIR/.github/workflows/zn-m2-256m-main-router.yml"
AUTO_MERGE="$ROOT_DIR/.github/workflows/auto-merge-deps.yml"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

for workflow in "$WF_1G" "$WF_256"; do
	if grep -Eq '^[[:space:]]+! (grep|find)' "$workflow"; then
		fail "bare negated command remains in $(basename "$workflow")"
	fi
	grep -Fq 'defconfig_log=' "$workflow" ||
		fail "defconfig diagnostics are not captured in $(basename "$workflow")"
	grep -Fq 'recursive dependency detected' "$workflow" ||
		fail "recursive Kconfig errors are not fatal in $(basename "$workflow")"
	grep -Fq 'timeout-minutes: 300' "$workflow" ||
		fail "compile timeout is missing in $(basename "$workflow")"
	if grep -Fq 'make -j1 V=s' "$workflow"; then
		fail "full serial rebuild remains in $(basename "$workflow")"
	fi
	if grep -Fq 'github.run_id' "$workflow"; then
		fail "ccache key remains run-specific in $(basename "$workflow")"
	fi
	grep -Fq "steps.ccache.outputs.cache-hit != 'true'" "$workflow" ||
		fail "ccache save is not limited to misses in $(basename "$workflow")"
	grep -Fq "steps.build_flags.outputs.firmware_release == 'true'" "$workflow" ||
		fail "artifact upload is not release-only in $(basename "$workflow")"
	grep -Fq 'test-upgrade-migrations.sh' "$workflow" ||
		fail "upgrade migration tests are missing from $(basename "$workflow")"
	grep -Fq 'test-healthcheck-hardening.sh' "$workflow" ||
		fail "healthcheck tests are missing from $(basename "$workflow")"
	grep -Fq 'test-ecm-module-deps.sh' "$workflow" ||
		fail "ECM dependency profile tests are missing from $(basename "$workflow")"
	grep -Fq 'test-cpubench-hardening.sh' "$workflow" ||
		fail "CoreMark tests are missing from $(basename "$workflow")"
	grep -Fq 'test-variant-contracts.sh' "$workflow" ||
		fail "variant tests are missing from $(basename "$workflow")"
	grep -Fq 'test-workflow-contracts.sh' "$workflow" ||
		fail "workflow tests are missing from $(basename "$workflow")"
	grep -Fq 'cleanup-releases:' "$workflow" ||
		fail "release cleanup is not a separate job in $(basename "$workflow")"
	grep -Fq 'continue-on-error: true' "$workflow" ||
		fail "release cleanup can still fail the build in $(basename "$workflow")"
	grep -Fq 'gh api --paginate' "$workflow" ||
		fail "release retention is not paginated in $(basename "$workflow")"
	if grep -Fq 'gh release list --repo' "$workflow"; then
		fail "bounded release listing remains in $(basename "$workflow")"
	fi
done

grep -Fq 'verify-ecm-module-deps.sh" "$ecm_module" required-only' "$WF_1G" ||
	fail "1G workflow does not use the required-only ECM dependency profile"
grep -Fq 'verify-ecm-module-deps.sh" "$ecm_module" pppoe-only' "$WF_256" ||
	fail "256M workflow does not use the PPPoE-only ECM dependency profile"

for setting in \
	'CONFIG_TARGET_ROOTFS_INITRAMFS is not set' \
	CONFIG_IPQ_MEM_PROFILE_1024=y \
	CONFIG_NSS_MEM_PROFILE_MEDIUM=y \
	CONFIG_PACKAGE_kmod-qca-nss-drv=y \
	CONFIG_PACKAGE_kmod-qca-nss-ecm=y; do
	grep -Fq "$setting" "$WF_1G" ||
		fail "1G workflow does not assert $setting"
done

grep -Fq -- '-DNSS_MEM_PROFILE_MEDIUM' "$WF_1G" ||
	fail "1G compiled NSS profile is not verified"
grep -Fq 'luci-app-homeproxy sing-box' "$WF_1G" ||
	fail "1G final manifest required packages are not verified"
grep -Fq 'Final manifest contains a forbidden 1G package' "$WF_1G" ||
	fail "1G final manifest forbidden packages are not verified"

if grep -Fq 'dependabot\[bot\]:dependabot/github_actions/' "$AUTO_MERGE"; then
	fail "GitHub Actions PRs can still self-validate and auto-merge"
fi
if grep -Fq 'allowed_kind="actions"' "$AUTO_MERGE"; then
	fail "action dependency auto-merge path remains"
fi

echo "workflow contract regression tests passed"
