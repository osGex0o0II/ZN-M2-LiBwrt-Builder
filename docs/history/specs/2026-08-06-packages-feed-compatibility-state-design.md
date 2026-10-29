# Packages Feed Compatibility State Design

## Problem

The builder repairs two known recursive dependency regressions in the pinned
`immortalwrt/packages` feed: FreeRADIUS OpenSSL selection and trafficshaper
firewall backend selection. The patch preflight now recognizes the pinned
pre-regression feed as safe, but `libwrt.sh` still unconditionally verifies the
post-patch layout. Both release variants therefore pass repository regression
tests and then fail while applying custom files.

The underlying design defect is duplicated state detection: patch application
and post-application validation make independent decisions about the same feed.

## Goals

- Use one classification result for patch application and final validation.
- Accept the exact structural signatures of known safe pre-regression packages.
- Accept patched or already-fixed modern package layouts.
- Fail closed for unknown, partially modified, or ambiguous layouts.
- Exercise the production classification and validation path in regression
  tests so a copied approximation cannot drift from runtime behavior.

## Non-goals

- Updating the pinned packages feed.
- Broadly accepting all older FreeRADIUS or trafficshaper versions.
- Removing compatibility patches or strict drift detection.
- Refactoring unrelated OpenWrt customization logic.

## Design

Move packages-feed compatibility state functions into a small sourceable shell
library. `libwrt.sh` and the regression test will both call this library.

Each package classifier returns one of three states:

- `modern-fixed`: the package contains the complete repaired structure.
- `legacy-safe`: the package matches every required pre-regression safety
  signature and contains none of the known regression markers.
- `invalid`: the structure is missing, partial, ambiguous, or unknown.

The orchestration flow for each compatibility patch is:

1. Classify the package before applying the patch.
2. If it is `modern-fixed`, use `git apply --reverse --check` only to distinguish
   a locally applied patch from an equivalent upstream fix for logging; do not
   mutate the package.
3. If it is `legacy-safe`, do not apply the forward patch.
4. Otherwise, attempt `git apply --check` and apply the patch only when the
   preflight succeeds.
5. Reclassify after any mutation and require `modern-fixed` or `legacy-safe`.
   Any other result is fatal.

Classification is structural rather than based only on a commit SHA. This
keeps the safety decision valid for an identical feed checkout while still
rejecting unexpected drift.

### FreeRADIUS states

`legacy-safe` requires all of the following:

- `PKG_VERSION:=3.2.8`
- the server package depends on `+freeradius3-common`
- the common package contains `+FREERADIUS3_OPENSSL:libopenssl`
- no `libopenssl-legacy` dependency

`modern-fixed` requires the complete conditional dependency pair:

```text
+FREERADIUS3_OPENSSL:libopenssl +FREERADIUS3_OPENSSL:libopenssl-legacy
```

### trafficshaper states

`legacy-safe` requires all of the following:

- `PKG_RELEASE:=3`
- the single trafficshaper package directly depends on
  `+iptables +IPV6:ip6tables`
- no `PACKAGE_nftables-` conditional dependency
- no `Package/trafficshaper-iptables` variant

`modern-fixed` requires both firewall variants and their complete backend
dependencies:

- `Package/trafficshaper` with `DEPENDS+= +nftables`
- `Package/trafficshaper-iptables` with
  `DEPENDS+= +iptables +IPV6:ip6tables +iptables-mod-conntrack-extra`

## Error Handling

- Missing feed worktree, Makefile, or compatibility patch remains fatal.
- The feed must have its own `.git` entry and Git top-level; an enclosing
  repository must not satisfy the worktree check.
- A forward patch that does not apply is accepted only when the shared
  classifier reports `modern-fixed` or `legacy-safe`.
- A partial modern layout is `invalid`, even if one expected marker exists.
- Commented-out Makefile markers are not active dependencies and must classify
  as `invalid`.
- Error output identifies the package and the rejected state so CI logs show
  whether classification failed before or after patch application.

## Testing

Regression tests use temporary git fixtures and call the same sourceable
library used by `libwrt.sh`.

Required scenarios:

1. Exact pinned `4db836e2d929b5f0d858000f99aa55bb0ab85100` package contents classify as
   `legacy-safe` and complete the full compatibility flow without mutation.
2. Patch target contents accept the forward patches, then classify as
   `modern-fixed`.
3. Already patched contents classify as `modern-fixed` and remain unchanged.
4. A partial FreeRADIUS guard is rejected.
5. A partial trafficshaper variant split is rejected.
6. An unknown version or release is rejected even when it resembles a safe
   legacy layout.
7. Commented-out legacy and modern markers are rejected.
8. A packages feed nested under an enclosing Git repository is rejected.
9. Real pre-patch fixtures apply both compatibility patches and pass a second
   idempotent repair run.
10. Existing repository, workflow, shell syntax, and source-contract tests
   remain green.

The test suite must first demonstrate the current CI failure before production
logic changes, then pass after the shared classifier is integrated.

## Success Criteria

- Both pinned-feed compatibility operations complete locally against the exact
  pinned package contents.
- Modern patch targets and already-patched layouts remain supported.
- Unknown or partial layouts fail closed.
- No duplicated legacy/modern classification logic remains between production
  code and tests.
