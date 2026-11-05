#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
WF_256="$ROOT_DIR/.github/workflows/zn-m2-256m-main-router.yml"
WF_618="$ROOT_DIR/.github/workflows/zn-m2-256m-6.18.yml"
AUTO_MERGE="$ROOT_DIR/.github/workflows/auto-merge-deps.yml"
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
	grep -Fq "if: steps.compile.outputs.status == 'success' && (steps.build_flags.outputs.firmware_release == 'true' || github.event_name == 'workflow_dispatch')" "$workflow" ||
		fail "dispatch builds can still discard the firmware artifact in $(basename "$workflow")"
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

grep -Fq "if: steps.compile.outputs.status == 'success' && (steps.build_flags.outputs.firmware_release == 'true' || github.event_name == 'workflow_dispatch')" "$WF_618" ||
	fail "6.18 dispatch builds can still discard the firmware artifact"

for workflow in "$WF_256" "$WF_618"; do
	grep -Fq 'push:' "$workflow" ||
		fail "main pushes do not build $(basename "$workflow")"
	grep -Fq "github.event_name == 'push'" "$workflow" ||
		fail "main pushes can publish a release from $(basename "$workflow")"
	grep -Fq 'prerelease: true' "$workflow" ||
		fail "new releases are not marked prerelease in $(basename "$workflow")"
	grep -Fq 'makeLatest: false' "$workflow" ||
		fail "unverified builds can become Latest in $(basename "$workflow")"
	grep -Fq 'test-dhcp-primer.sh' "$workflow" ||
		fail "DHCP primer test is missing from $(basename "$workflow")"
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

grep -Fq 'Skip: author/head not allowed' "$AUTO_MERGE" ||
	fail "auto-merge no longer rejects untrusted authors or head branches"
grep -Fq '. == "deps/libwrt-6.12.env" or' "$AUTO_MERGE" ||
	fail "auto-merge no longer allows the 6.12 pin file"
grep -Fq '. == "deps/immortalwrt-6.18.env"' "$AUTO_MERGE" ||
	fail "auto-merge no longer allows the 6.18 pin file"
for required_check in \
	'Build ZN-M2 LiBwrt 6.12 NSS' \
	'Build ZN-M2 ImmortalWrt 6.18 PPE'; do
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

# Upstream revisions are resolved at build time from the tracked branches, so the
# scheduled pin-bumping workflow must not come back.
[ ! -e "$ROOT_DIR/.github/workflows/auto-update-pinned-deps.yml" ] ||
	fail "scheduled dependency pin updates are back"
grep -Fq 'scripts/resolve-latest-upstreams.sh' "$WF_256" ||
	fail "6.12 workflow does not resolve tracked upstream refs"
grep -Fq 'scripts/resolve-latest-upstreams.sh' "$WF_618" ||
	fail "6.18 workflow does not resolve tracked upstream refs"
grep -Fq 'test-immortalwrt-6.18-contracts.sh' "$WF_618" ||
	fail "6.18 workflow does not run its contract test"
grep -Fq 'test-immortalwrt-6.18-contracts.sh' "$WF_256" ||
	fail "6.12 workflow does not run the ImmortalWrt 6.18 contract test"

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
if grep -Fq 'patch_packages_feed_dependencies' "$ROOT_DIR/libwrt-6.12.sh"; then
	fail "obsolete packages feed compatibility patch hook is still present"
fi
if grep -Fq 'test-packages-feed-patches.sh' "$WF_256"; then
	fail "256M workflow still runs the removed packages feed compatibility test"
fi

for workflow in "$AUTO_MERGE"; do
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

# Each promoted profile owns a separately named workflow so the Actions list
# shows one entry per variant instead of a single generic "experimental" build.
for spec in \
	"zn-m2-256m-viking-nss.yml|ZN-M2 ImmortalWrt 6.18 NSS|immortalwrt-viking-main-nss|zn-m2-viking-6.18-nss" \
	"zn-m2-256m-lede-nss.yml|ZN-M2 LEDE 6.12 NSS|lede-master-nss|zn-m2-lede-6.12-nss" \
	"zn-m2-256m-fanchmwrt-fwx.yml|ZN-M2 FanchmWrt 6.12 FWX|fanchmwrt-25.12|zn-m2-fanchmwrt-6.12-fwx"; do
	file="${spec%%|*}"
	rest="${spec#*|}"
	title="${rest%%|*}"
	rest="${rest#*|}"
	profile="${rest%%|*}"
	slug="${rest#*|}"
	path="$ROOT_DIR/.github/workflows/$file"
	[ -f "$path" ] || fail "missing promoted workflow $file"
	grep -Fq "name: $title" "$path" ||
		fail "$file does not carry the display name $title"
	grep -Fq "profile: $profile" "$path" ||
		fail "$file does not build $profile"
	grep -Fq "tag_slug: $slug" "$path" ||
		fail "$file uses an unexpected release tag slug"
	grep -Fq 'uses: ./.github/workflows/build-profile.yml' "$path" ||
		fail "$file does not reuse the shared build workflow"
	grep -Fq 'uses: ./.github/workflows/publish-profile.yml' "$path" ||
		fail "$file cannot publish a release"
done

[ ! -e "$ROOT_DIR/.github/workflows/build-experimental.yml" ] ||
	fail "the generic experimental workflow must not coexist with the promoted builds"

PUBLISH="$ROOT_DIR/.github/workflows/publish-profile.yml"
[ -f "$PUBLISH" ] || fail "shared release workflow is missing"
grep -Fq 'gh release create' "$PUBLISH" ||
	fail "shared release workflow does not create a release"

bash "$ROOT_DIR/tests/test-workflow-subscriptions.sh"
echo "workflow contract regression tests passed"
