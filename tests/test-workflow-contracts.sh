#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
WF_256="$ROOT_DIR/.github/workflows/zn-m2-256m-main-router.yml"
WF_618="$ROOT_DIR/.github/workflows/zn-m2-256m-6.18.yml"
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
done

MATURE_PUBLISH="$ROOT_DIR/.github/workflows/publish-mature.yml"
[ -f "$MATURE_PUBLISH" ] || fail "reusable mature release workflow missing"
for pair in \
  "cleanup-releases:" \
  "continue-on-error: true" \
  "gh api --paginate" \
  "prerelease: false" \
  "makeLatest: true" \
  'RELEASE_TAG_SUFFIX: ${{ inputs.firmware_tag }}'; do
  grep -Fq "$pair" "$MATURE_PUBLISH" ||
    fail "mature release workflow lacks $pair"
done
if grep -Fq 'gh release list --repo' "$MATURE_PUBLISH"; then
  fail "bounded mature release listing remains"
fi
for workflow in "$WF_256" "$WF_618"; do
  grep -Fq 'uses: ./.github/workflows/publish-mature.yml' "$workflow" ||
    fail "mature firmware line does not reuse the release workflow"
  # String dispatch inputs and needs.*.outputs are not reliable in a
  # reusable-workflow caller's if; the publish gate must use a boolean input
  # and the build job result.
  grep -Fq "if: needs.build.result == 'success' && (github.event_name == 'schedule' || inputs.firmware_release)" "$workflow" ||
    fail "reusable release caller can be skipped before reading build outputs"
  grep -Fq 'type: boolean' "$workflow" ||
    fail "mature release dispatch flag is not a boolean input"
  if grep -Fq "github.event.inputs.firmware_release" "$workflow"; then
    fail "reusable release caller still reads github.event.inputs in its if"
  fi
  if grep -Fq "inputs.firmware_release == 'true'" "$workflow"; then
    fail "reusable release caller still compares a string dispatch input in its if"
  fi
done

grep -Fq "if: steps.compile.outputs.status == 'success' && (steps.build_flags.outputs.firmware_release == 'true' || github.event_name == 'workflow_dispatch')" "$WF_618" ||
	fail "6.18 dispatch builds can still discard the firmware artifact"

for workflow in "$WF_256" "$WF_618"; do
	grep -Fq 'push:' "$workflow" ||
		fail "main pushes do not build $(basename "$workflow")"
	grep -Fq "github.event_name == 'push'" "$workflow" ||
		fail "main pushes can publish a release from $(basename "$workflow")"
	grep -Fq 'test-dhcp-primer.sh' "$workflow" ||
		fail "DHCP primer test is missing from $(basename "$workflow")"
done

grep -Fq 'verify-ecm-module-deps.sh" "$ecm_module" pppoe-only' "$WF_256" ||
	fail "256M workflow does not use the PPPoE-only ECM dependency profile"

# The pin update generator this helper served was removed; the workflow must
# not come back without a generator and a fresh security review.
[ ! -e "$ROOT_DIR/.github/workflows/auto-merge-deps.yml" ] ||
	fail "dormant dependency auto-merge workflow returned"

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
grep -Fq 'name: Ensure device tree tools' "$WF_618" ||
	fail "6.18 workflow does not install device-tree-compiler before DTB validation"
grep -Fq 'name: Ensure device tree tools' "$WF_256" ||
	fail "6.12 workflow does not install device-tree-compiler before DTB validation"

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
grep -Fq '^experimental-' "$PRUNE_CACHES" ||
	fail 'cache pruning does not drop legacy experimental caches'
grep -Fq '^profile-' "$PRUNE_CACHES" ||
	fail 'cache pruning does not group profile caches'
grep -Fq 'CACHE_QUOTA_BYTES: "4294967296"' "$PRUNE_CACHES" ||
	fail 'cache pruning does not enforce the 4GB quota'
grep -Fq '"apt" : "other"' "$PRUNE_CACHES" ||
	fail 'cache pruning does not group apt download caches separately'
grep -Fq 'keep = (family == "apt") ? 1 : 2' "$PRUNE_CACHES" ||
	fail 'cache pruning keeps more than one apt download cache generation'
if grep -Fq 'patch_packages_feed_dependencies' "$ROOT_DIR/adapters/libwrt-6.12.sh"; then
	fail "obsolete packages feed compatibility patch hook is still present"
fi
if grep -Fq 'test-packages-feed-patches.sh' "$WF_256"; then
	fail "256M workflow still runs the removed packages feed compatibility test"
fi

# Each profile owns a separately named workflow so the Actions list shows one
# entry per variant instead of a single generic build.
for spec in \
	"zn-m2-256m-viking-nss.yml|ZN-M2 ImmortalWrt 6.18 NSS|immortalwrt-viking-main-nss|zn-m2-viking-6.18-nss" \
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

PUBLISH="$ROOT_DIR/.github/workflows/publish-profile.yml"
[ -f "$PUBLISH" ] || fail "shared release workflow is missing"
grep -Fq 'gh release create' "$PUBLISH" ||
	fail "shared release workflow does not create a release"
grep -Fq -- '--name "firmware-${PROFILE}"' "$PUBLISH" ||
	fail "shared release workflow downloads the wrong artifact name"

# The reusable build workflow is a building block, not an experiment, and its
# display name is what users see in the Actions sidebar.
BUILD="$ROOT_DIR/.github/workflows/build-profile.yml"
[ -f "$BUILD" ] || fail "shared build workflow is missing"
grep -Fq 'name: Build ZN-M2 profile' "$BUILD" ||
	fail "shared build workflow carries a stale display name"
grep -Fq 'name: Build ${{ inputs.title }}' "$BUILD" ||
	fail "profile build jobs do not use the public display name"
grep -Fq 'title:' "$BUILD" ||
	fail "profile build workflow does not accept the display name input"
grep -Fq 'name: firmware-${{ inputs.profile }}' "$BUILD" ||
	fail "profile build artifact is not named like a firmware artifact"
grep -Fq 'key: profile-${{ runner.os }}' "$BUILD" ||
	fail "profile cache key still uses a development-only namespace"

# Releases stay minimal: only the two flashing images are attached, and the
# checksums live in the generated Chinese notes instead of extra assets.
for wf in zn-m2-256m-main-router.yml zn-m2-256m-6.18.yml; do
	path="$ROOT_DIR/.github/workflows/$wf"
	grep -Fq 'scripts/release-notes.sh' "$path" ||
		fail "$wf does not generate the Chinese release notes"
	grep -Fq 'release-notes.sh" "$PROFILE_ID" "$release_dir" "$release_dir/BUILD-MANIFEST.txt"' "$path" ||
		fail "$wf does not pass build provenance to the release notes"
done
grep -Fq 'artifacts: firmware/*-factory.ubi,firmware/*-sysupgrade.bin' "$MATURE_PUBLISH" ||
  fail "mature release still attaches the full build artifact set"
grep -Fq 'bash scripts/release-notes.sh "$PROFILE" release release/BUILD-MANIFEST.txt' "$PUBLISH" ||
	fail "shared release workflow does not generate notes with source/build provenance"
if grep -Fq 'gh release create "$tag" release/* ' "$PUBLISH"; then
	fail "shared release workflow still uploads every staged file"
fi
grep -Fq -- '--latest' "$PUBLISH" ||
	fail "profile releases do not update the GitHub Latest badge"
if grep -Fq -- '--latest=false' "$PUBLISH"; then
	fail "profile releases opt out of the GitHub Latest badge"
fi

# The publish job deletes stale artifacts, and artifact deletion needs
# actions: write. actions: read silently turned every publish into a failure
# after the release itself had already been created.
grep -Fq 'actions: write' "$PUBLISH" ||
	fail "shared release workflow cannot delete stale artifacts"
for wf in zn-m2-256m-fanchmwrt-fwx.yml zn-m2-256m-viking-nss.yml; do
	path="$ROOT_DIR/.github/workflows/$wf"
	grep -Fq 'actions: write' "$path" ||
		fail "$wf does not grant artifact cleanup to the publish job"
done
# Cleanup is housekeeping: a failed delete must warn, not fail the job.
grep -Fq 'failed to prune artifact' "$PUBLISH" ||
	fail "shared release workflow treats artifact cleanup as fatal"

# Documentation-only pull requests must not spend two hours on a cross build,
# while the required check still has to report a conclusion on every PR.
for wf in zn-m2-256m-main-router.yml zn-m2-256m-6.18.yml; do
	path="$ROOT_DIR/.github/workflows/$wf"
	grep -Fq 'name: Detect build-relevant changes' "$path" ||
		fail "$wf lacks the build-relevant change detector"
	grep -Fq 'needs: changes' "$path" ||
		fail "$wf does not gate the build on the change detector"
	grep -Fq 'needs.changes.outputs.code' "$path" ||
		fail "$wf does not read the detected change scope"
done

echo "workflow contract regression tests passed"

# Required check names remain stable while compilation becomes an optional
# prerequisite selected by the file scope classifier.
for workflow in "$WF_256" "$WF_618"; do
  grep -Fq 'name: Fast profile validation' "$workflow" ||
    fail "fast PR validation missing from $(basename "$workflow")"
  grep -Fq 'scripts/ci-change-scope.py' "$workflow" ||
    fail "change scope classifier missing from $(basename "$workflow")"
  grep -Fq 'scripts/ci-fast-validation.sh' "$workflow" ||
    fail "fast regression runner missing from $(basename "$workflow")"
  grep -Fq 'run: bash scripts/ci-gate.sh' "$workflow" ||
    fail "shared fail-closed PR gate missing from $(basename "$workflow")"
  grep -Fq "always() && github.event_name == 'pull_request'" "$workflow" ||
    fail "fail-closed required gate missing from $(basename "$workflow")"
  if grep -Fq -- "- 'tests/**'" "$workflow"; then
    fail "tests alone still trigger full main branch builds in $(basename "$workflow")"
  fi
done

for pair in \
  "$WF_256|LiBwrt 6.12 NSS" \
  "$WF_618|ImmortalWrt 6.18 PPE"; do
  workflow="${pair%%|*}"
  label="${pair#*|}"
  grep -Fq "name: Build ZN-M2 $label" "$workflow" ||
    fail "required check name changed for $label"
  grep -Fq "name: Compile ZN-M2 $label" "$workflow" ||
    fail "real compile job not separated from required check for $label"
done

# Verify that the refactored publish call passes both identity fields.
for spec in \
  "$WF_256|zn-m2-libwrt-6.12-nss" \
  "$WF_618|zn-m2-immortalwrt-6.18-ppe"; do
  workflow="${spec%%|*}"
  slug="${spec#*|}"
  grep -Fq "firmware_tag: $slug" "$workflow" ||
    fail "$slug is not wired to the matching reusable release publisher"
  grep -Fq 'file_version: ${{ needs.build.outputs.file_version }}' "$workflow" ||
    fail "$slug does not publish the compiled build version"
done
grep -Fq 'tag: v${{ inputs.file_version }}-${{ inputs.firmware_tag }}' "$MATURE_PUBLISH" ||
  fail "reusable publisher assembles the wrong release tag"
grep -Fq 'artifacts: firmware/*-factory.ubi,firmware/*-sysupgrade.bin' "$MATURE_PUBLISH" ||
  fail "reusable publisher must attach exactly both firmware images"

grep -Fq 'name: Verify affected Viking NSS profile' "$WF_256" ||
  fail "Viking profile changes are not built before merge"
grep -Fq 'name: Verify affected FanchmWrt FWX profile' "$WF_256" ||
  fail "FanchmWrt profile changes are not built before merge"
grep -Fq 'workflow_call:' "$ROOT_DIR/.github/workflows/build-profile.yml" ||
  fail "Viking and FanchmWrt reusable build workflow missing"
test -f "$ROOT_DIR/.github/workflows/pr-validation.yml" ||
  fail "standalone fast PR workflow missing"
