#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
WF_256="$ROOT_DIR/.github/workflows/zn-m2-256m-main-router.yml"
WF_618="$ROOT_DIR/.github/workflows/zn-m2-256m-6.18.yml"
AUTO_MERGE="$ROOT_DIR/.github/workflows/auto-merge-deps.yml"
AUTO_UPDATE="$ROOT_DIR/.github/workflows/auto-update-pinned-deps.yml"
PRUNE_CACHES="$ROOT_DIR/.github/workflows/prune-caches.yml"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

for workflow in "$WF_256"; do
	if grep -Eq '^[[:space:]]+! (grep|find)' "$workflow"; then
		fail "bare negated command remains in $(basename "$workflow")"
	fi
	grep -Fq 'defconfig_log=' "$workflow" ||
		fail "defconfig diagnostics are not captured in $(basename "$workflow")"
	grep -Fq 'recursive dependency detected' "$workflow" ||
		fail "recursive Kconfig errors are not fatal in $(basename "$workflow")"
	grep -Fq 'timeout-minutes: 270' "$workflow" ||
		fail "compile timeout is missing in $(basename "$workflow")"
	grep -Fq 'timeout-minutes: 70' "$workflow" ||
		fail "init step timeout is not extended in $(basename "$workflow")"
	grep -Fq 'timeout 22m bash "$init_script"' "$workflow" ||
		fail "init script timeout is not extended in $(basename "$workflow")"
	grep -Fq 'for attempt in 1 2 3' "$workflow" ||
		fail "init script is not retried in $(basename "$workflow")"
	grep -Fq 'Restore apt download cache' "$workflow" ||
		fail "apt download cache is not restored in $(basename "$workflow")"
	grep -Fq 'Save apt download cache' "$workflow" ||
		fail "apt download cache is not saved in $(basename "$workflow")"
	grep -Fq 'apt-archives-${{ runner.os }}-${{ steps.image.outputs.version }}' "$workflow" ||
		fail "apt download cache key is not bound to the runner image in $(basename "$workflow")"
	grep -Fq 'apt clean -y disabled by CI to keep the download cache' "$workflow" ||
		fail "the pinned installer still wipes the apt download cache in $(basename "$workflow")"
	grep -Fq 'Binary::apt::APT::Keep-Downloaded-Packages "true"' "$workflow" ||
		fail "apt(8) still deletes the downloaded packages in $(basename "$workflow")"
	grep -Fq "steps.init_env.outputs.apt_cache_count != '0'" "$workflow" ||
		fail "an empty apt download cache can still be saved in $(basename "$workflow")"
	grep -Fq 'sudo apt-mark hold "$kernel_pkg"' "$workflow" ||
		fail "runner kernel upgrades are not pinned in $(basename "$workflow")"
	grep -Fq 'timeout --foreground 30m make -j1 V=s' "$workflow" ||
		fail "parallel build failures are not retried serially in $(basename "$workflow")"
	grep -Fq '::warning::Parallel build failed' "$workflow" ||
		fail "parallel build fallback is not announced in $(basename "$workflow")"
	if grep -Fq 'make -j1 V=s' "$workflow" &&
	   ! grep -Fq 'timeout --foreground 30m make -j1 V=s' "$workflow"; then
		fail "unbounded serial rebuild remains in $(basename "$workflow")"
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

grep -Fq 'verify-ecm-module-deps.sh" "$ecm_module" pppoe-only' "$WF_256" ||
	fail "256M workflow does not use the PPPoE-only ECM dependency profile"

if grep -Fq 'dependabot\[bot\]:dependabot/github_actions/' "$AUTO_MERGE"; then
	fail "GitHub Actions PRs can still self-validate and auto-merge"
fi
if grep -Fq 'allowed_kind="actions"' "$AUTO_MERGE"; then
	fail "action dependency auto-merge path remains"
fi

# The updater opens its pull request with the automation PAT, so it is authored
# by the repository owner; older runs used the built-in GITHUB_TOKEN (the
# github-actions app identity) or the github-actions[bot] login. The auto-merge
# identity gate must accept all three, and must stay locked to the pinned
# dependency update branch.
merge_allow_rule_count="$(grep -cE '^[[:space:]]+[^[:space:]#].*:automation/pinned-deps-update\)[[:space:]]*$' "$AUTO_MERGE" || true)"
[ "$merge_allow_rule_count" -eq 1 ] ||
	fail "auto-merge must declare exactly one dependency PR identity rule (found ${merge_allow_rule_count})"

merge_allow_rule="$(grep -E '^[[:space:]]+[^[:space:]#].*:automation/pinned-deps-update\)[[:space:]]*$' "$AUTO_MERGE" | head -n 1)"
merge_allow_rule="${merge_allow_rule#"${merge_allow_rule%%[![:space:]]*}"}"
merge_allow_rule="${merge_allow_rule%)}"
merge_allow_expected='github-actions\[bot\]:automation/pinned-deps-update|app/github-actions:automation/pinned-deps-update|osGex0o0II:automation/pinned-deps-update'
[ "$merge_allow_rule" = "$merge_allow_expected" ] ||
	fail "auto-merge identity rule is not limited to the pinned updater identities: ${merge_allow_rule}"
if printf '%s' "$merge_allow_rule" | grep -q '[*?]'; then
	fail "auto-merge identity rule contains a wildcard: ${merge_allow_rule}"
fi

# Bot-authored pull requests stall the pull_request validation builds on manual
# approval, so the updater must create them with the automation PAT instead of
# the built-in GITHUB_TOKEN.
if grep -Fq 'secrets.GITHUB_TOKEN' "$AUTO_UPDATE"; then
	fail "auto-update still uses GITHUB_TOKEN (bot-authored PRs require manual approval)"
fi

grep -Fq 'Skip: author/head not allowed' "$AUTO_MERGE" ||
	fail "auto-merge no longer rejects untrusted authors or head branches"
grep -Fq '. == "deps/pinned-deps.env" or' "$AUTO_MERGE" ||
	fail "auto-merge no longer allows the 6.12 pin file"
grep -Fq '. == "deps/linux-6.18.env"' "$AUTO_MERGE" ||
	fail "auto-merge no longer allows the 6.18 pin file"
for required_check in \
	'Build ZN-M2 256M Main Router firmware' \
	'Build ZN-M2 256M 6.18 firmware'; do
	grep -Fq "$required_check" "$AUTO_MERGE" ||
		fail "auto-merge no longer requires ${required_check}"
done

# The pull request check rollup stays empty when the validation builds run as
# workflow_dispatch on the update branch, so the gate must read the head commit's
# own check runs, restrict them to GitHub Actions, and hand the merge to GitHub.
grep -Fq 'headRefOid' "$AUTO_MERGE" ||
	fail "auto-merge no longer resolves the pull request head commit"
grep -Fq 'commits/${head_sha}/check-runs' "$AUTO_MERGE" ||
	fail "auto-merge no longer reads the head commit check runs"
grep -Fq '.app == "github-actions"' "$AUTO_MERGE" ||
	fail "auto-merge accepts check runs from apps other than GitHub Actions"
grep -Fq '.status == "completed" and .conclusion == "success"' "$AUTO_MERGE" ||
	fail "auto-merge no longer requires completed successful check runs"
if grep -Fq 'statusCheckRollup' "$AUTO_MERGE"; then
	fail "auto-merge still trusts the empty pull request check rollup"
fi
grep -Fq -- '--auto' "$AUTO_MERGE" ||
	fail "auto-merge does not defer the merge to GitHub auto-merge"
grep -Fq -- '--match-head-commit' "$AUTO_MERGE" ||
	fail "auto-merge is not bound to the validated head commit"
grep -Fq 'Auto-merge unavailable; falling back to a direct squash merge' "$AUTO_MERGE" ||
	fail "auto-merge failure has no direct-merge fallback"

grep -Fq 'secrets.AUTO_UPDATE_TOKEN' "$AUTO_UPDATE" ||
	fail "auto-update does not require a workflow-capable repository token"
grep -Fq 'AUTO_UPDATE_TOKEN is not configured' "$AUTO_UPDATE" ||
	fail "auto-update token failure is not explicit"
grep -Fq 'OPENWRT_6_18_REPO_URL: https://github.com/VIKINGYFY/immortalwrt.git' "$AUTO_UPDATE" ||
	fail "auto-update does not track the 6.18 source"
grep -Fq 'PINNED_DEPS_6_18_FILE: deps/linux-6.18.env' "$AUTO_UPDATE" ||
	fail "auto-update does not maintain the 6.18 pin file"
grep -Fq 'git add "$PINNED_DEPS_FILE" "$PINNED_DEPS_6_18_FILE"' "$AUTO_UPDATE" ||
	fail "auto-update does not commit both pin files"
grep -Fq 'gh workflow run zn-m2-256m-6.18.yml' "$AUTO_UPDATE" ||
	fail "auto-update does not dispatch the 6.18 validation build"
grep -Fq 'test-6.18-contracts.sh' "$WF_618" ||
	fail "6.18 workflow does not run its contract test"
grep -Fq 'test-6.18-contracts.sh' "$WF_256" ||
	fail "6.12 workflow does not run the 6.18 contract test"

[ -f "$PRUNE_CACHES" ] || fail 'cache pruning workflow is missing'
grep -Fq 'actions: write' "$PRUNE_CACHES" ||
	fail 'cache pruning cannot delete caches'
grep -Fq 'actions/caches?per_page=100&sort=created_at&direction=desc' "$PRUNE_CACHES" ||
	fail 'cache pruning does not enumerate every cache'
grep -Fq 'refs\/pull\/' "$PRUNE_CACHES" ||
	fail 'cache pruning does not drop pull request caches'
grep -Fq 'inputs.dry_run' "$PRUNE_CACHES" ||
	fail 'cache pruning has no dry-run switch'
grep -Fq 'variant = "6.18"' "$PRUNE_CACHES" ||
	fail 'cache pruning does not group the 6.18 variant'
grep -Fq 'variant = "6.12"' "$PRUNE_CACHES" ||
	fail 'cache pruning does not group the 6.12 variant'
grep -Fq 'zn-m2-1g' "$PRUNE_CACHES" ||
	fail 'cache pruning does not drop the retired 1G caches'
grep -Fq 'CACHE_QUOTA_BYTES: "8589934592"' "$PRUNE_CACHES" ||
	fail 'cache pruning does not enforce the 8GB quota'
grep -Fq '"apt" : "other"' "$PRUNE_CACHES" ||
	fail 'cache pruning does not group apt download caches separately'
grep -Fq 'keep = (family == "apt") ? 1 : 2' "$PRUNE_CACHES" ||
	fail 'cache pruning keeps more than one apt download cache generation'
grep -Fq 'patch_packages_feed_dependencies' "$ROOT_DIR/libwrt.sh" ||
	fail "packages feed compatibility patch hook is missing"
grep -Fq 'test-packages-feed-patches.sh' "$WF_256" ||
	fail "256M workflow does not validate packages feed compatibility patches"

for workflow in "$AUTO_UPDATE" "$AUTO_MERGE"; do
	upsert='gh label create "$name" --color "$color" --description "$description" --force'
	if [ "$(grep -Fc "$upsert" "$workflow")" -ne 1 ]; then
		fail "label setup is not a single force-idempotent operation in $(basename "$workflow")"
	fi
	if grep -Fq 'gh label view "$name"' "$workflow"; then
		fail "unsupported gh label view remains in $(basename "$workflow")"
	fi
	if grep -Fq 'gh label edit "$name"' "$workflow"; then
		fail "split label edit path remains in $(basename "$workflow")"
	fi
done

echo "workflow contract regression tests passed"
