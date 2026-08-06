# Packages Feed Compatibility State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make packages-feed patching and validation use one fail-closed state classifier so the pinned safe legacy feed and repaired modern feeds both build.

**Architecture:** Add a sourceable POSIX shell library that classifies and repairs each supported package. `libwrt.sh` and its regression test call the same public `packages_feed_repair` function, eliminating copied state logic and mismatched postconditions.

**Tech Stack:** POSIX shell, Git patch preflight, grep-based Makefile structural validation, GitHub Actions.

## Global Constraints

- The exact pinned packages feed `4db836e2d929b5f0d858000f99aa55bb0ab85100` must be accepted without mutation.
- Modern repaired structures and already-applied patches must remain accepted.
- Unknown, partial, or ambiguous structures must fail closed.
- No network access is required by the committed regression tests.
- Existing release variant behavior outside packages-feed compatibility is unchanged.

---

### Task 1: Add runtime-path regression tests

**Files:**
- Modify: `tests/test-packages-feed-patches.sh`

**Interfaces:**
- Consumes: `scripts/packages-feed-compat.sh`
- Produces: executable expectations for `packages_feed_patch_state FEED_DIR PATCH_FILE` and `packages_feed_repair FEED_DIR PATCH_DIR`

- [ ] **Step 1: Source the wished-for production library and add fixture helpers**

Add an existence check and source statement for `scripts/packages-feed-compat.sh`. Add temporary git fixture helpers that write minimal legacy-safe, modern-fixed, partial, and unknown Makefiles under `net/freeradius3` and `net/trafficshaper`.

The legacy fixture must include:

```sh
PKG_VERSION:=3.2.8
DEPENDS:=+freeradius3-common
DEPENDS:= +FREERADIUS3_OPENSSL:libopenssl +libcap
DEPENDS:=+freeradius3-common
PKG_RELEASE:=3
DEPENDS:=+tc +iptables +IPV6:ip6tables +iptables-mod-conntrack-extra
```

The modern fixture must include all repaired markers, including three complete FreeRADIUS OpenSSL dependency pairs and both complete trafficshaper variants.

- [ ] **Step 2: Assert complete compatibility behavior**

Add assertions equivalent to:

```sh
[ "$(packages_feed_patch_state "$legacy_feed" "$freeradius_patch")" = legacy-safe ]
[ "$(packages_feed_patch_state "$legacy_feed" "$trafficshaper_patch")" = legacy-safe ]
packages_feed_repair "$legacy_feed" "$PATCH_DIR"
[ -z "$(git -C "$legacy_feed" status --short)" ]

[ "$(packages_feed_patch_state "$modern_feed" "$freeradius_patch")" = modern-fixed ]
[ "$(packages_feed_patch_state "$modern_feed" "$trafficshaper_patch")" = modern-fixed ]
packages_feed_repair "$modern_feed" "$PATCH_DIR"

[ "$(packages_feed_patch_state "$partial_feed" "$freeradius_patch")" = invalid ]
if packages_feed_repair "$partial_feed" "$PATCH_DIR"; then
	fail 'partial packages feed was accepted'
fi
```

When an OpenWrt source path is supplied, copy its two exact pinned Makefiles to a temporary git fixture, run `packages_feed_repair`, require both states to be `legacy-safe`, and require a clean worktree.

- [ ] **Step 3: Run the focused test and verify RED**

Run:

```sh
sh tests/test-packages-feed-patches.sh
```

Expected: `FAIL: missing shared packages feed compatibility library` because production code does not yet expose the shared runtime path.

### Task 2: Implement the shared fail-closed classifier

**Files:**
- Create: `scripts/packages-feed-compat.sh`

**Interfaces:**
- Produces: `packages_feed_freeradius_state MAKEFILE`, `packages_feed_trafficshaper_state MAKEFILE`, `packages_feed_patch_state FEED_DIR PATCH_FILE`, and `packages_feed_repair FEED_DIR PATCH_DIR`

- [ ] **Step 1: Implement FreeRADIUS classification**

`packages_feed_freeradius_state` prints exactly one of `modern-fixed`, `legacy-safe`, or `invalid` and returns success for all three classifications. It reports `modern-fixed` only when all three selector lines contain the complete OpenSSL pair and no bare selector remains. It reports `legacy-safe` only for version `3.2.8`, two bare `freeradius3-common` selectors, the old common OpenSSL dependency, and no `libopenssl-legacy` marker.

- [ ] **Step 2: Implement trafficshaper classification**

`packages_feed_trafficshaper_state` reports `modern-fixed` only when the default block, nftables variant, iptables variant, full backend dependencies, and both build invocations exist with no recursive `PACKAGE_nftables-` selector. It reports `legacy-safe` only for release `3`, direct iptables dependencies, and no nftables or split-variant markers.

- [ ] **Step 3: Implement state-driven repair**

`packages_feed_repair` must:

```sh
case "$state" in
	modern-fixed) log_without_mutation ;;
	legacy-safe) log_legacy_skip ;;
	invalid)
		git -C "$feed_dir" apply --check "$patch_file" || return 1
		git -C "$feed_dir" apply "$patch_file" || return 1
		;;
esac
final_state="$(packages_feed_patch_state "$feed_dir" "$patch_file")"
case "$final_state" in
	modern-fixed|legacy-safe) ;;
	*) return 1 ;;
esac
```

It validates the feed git worktree, both Makefiles, both patch files, and rejects unknown patch basenames.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run:

```sh
sh tests/test-packages-feed-patches.sh
```

Expected: `packages feed compatibility state tests passed`.

### Task 3: Integrate the shared repair path into the build

**Files:**
- Modify: `libwrt.sh`
- Modify: `tests/test-package-source-contracts.sh`

**Interfaces:**
- Consumes: `packages_feed_repair FEED_DIR PATCH_DIR`
- Produces: one production code path shared with the regression test

- [ ] **Step 1: Add a contract assertion before production integration**

Require `libwrt.sh` to source `scripts/packages-feed-compat.sh` and call:

```sh
packages_feed_repair "$packages_feed_dir" "$builder_root/patches/packages"
```

- [ ] **Step 2: Run the contract test and verify RED**

Run:

```sh
sh tests/test-package-source-contracts.sh
```

Expected: failure stating that the shared packages-feed compatibility library or repair call is missing.

- [ ] **Step 3: Replace duplicated production logic**

Replace the nested legacy classifier, patch loop, and unconditional post-patch guards in `patch_packages_feed_dependencies` with a guarded source of the shared library and one `packages_feed_repair` call. Preserve the existing section heading.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```sh
sh tests/test-packages-feed-patches.sh
sh tests/test-package-source-contracts.sh
```

Expected: both pass.

### Task 4: Verify the exact pinned feed and full repository

**Files:**
- Modify only if a test exposes a defect in Tasks 1-3.

**Interfaces:**
- Consumes: committed tests and exact upstream pinned Makefiles
- Produces: verification evidence for release rebuilds

- [ ] **Step 1: Verify exact upstream pinned contents**

Download the two Makefiles from the immutable raw URLs for commit `4db836e2d929b5f0d858000f99aa55bb0ab85100` into a temporary git fixture, run `tests/test-packages-feed-patches.sh FIXTURE_ROOT`, then delete the fixture.

Expected: both packages classify as `legacy-safe`, the full repair flow passes, and `git status --short` is empty.

- [ ] **Step 2: Run all relevant local checks**

Run:

```sh
bash -n libwrt.sh
bash -n scripts/packages-feed-compat.sh
bash -n tests/test-packages-feed-patches.sh
sh tests/test-packages-feed-patches.sh
sh tests/test-package-source-contracts.sh
sh tests/test-workflow-contracts.sh
git diff --check
```

Expected: every command exits zero with no syntax or whitespace errors.

- [ ] **Step 3: Commit the implementation**

```sh
git add libwrt.sh scripts/packages-feed-compat.sh tests/test-packages-feed-patches.sh tests/test-package-source-contracts.sh
git commit -m "fix: unify packages feed compatibility validation"
```

- [ ] **Step 4: Push and dispatch release builds**

Push `codex/packages-feed-build-fix`, then dispatch both release workflows with `firmware_release=true`. Read each run once to confirm the new commit SHA and initial status; do not wait for completion.

## Self-review

- The plan covers every approved state and failure mode.
- Runtime and tests consume the same library and repair entrypoint.
- All production changes follow a failing focused test.
- No unrelated build behavior or dependency pin changes are included.
