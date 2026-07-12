# Firmware Hardening Design

## Scope

Repair every actionable issue from the two-variant audit, preserve the verified
256M NSS behavior, then publish the fixes to `main` and start both release
builds. PPPoE hardware forwarding remains a post-build device acceptance check.

## Runtime And Upgrade Safety

Add one common, idempotent upgrade migration for the exact legacy public root
hash and the exact three-rule IPv6 firewall deletion footprint. The known hash
is cleared to the documented first-login state, where LuCI can set a new
password and Dropbear still rejects blank-password SSH. Add a 256M-only
migration for the exact old fixed-DNS tuple so custom resolver policies remain
untouched.

Healthcheck state lives in a root-owned mode-0700 directory and is updated by
temporary-file rename. HomeProxy is considered expected only when a client
node, custom outbound, or server is configured. CoreMark results require a
successful process and validation marker.

## Build And Release Integrity

Match the pinned packages feed's sing-box variant relationship. Explicitly lock
the 1G IPQ1024, NSS MEDIUM, base NSS/ECM and no-initramfs contract. Replace bare
negative shell commands with explicit failing branches, reject recursive
defconfig diagnostics, validate the 1G final manifest, and add compiled NSS
profile checks.

Use stable content-addressed ccache keys, save only on misses, remove the full
serial rebuild, bound compile time, and upload artifacts only for release
builds. Release retention becomes a paginated, non-critical follow-up job.
GitHub Actions dependency PRs require manual review instead of self-validating
auto-merge.

## Repository Policy And Delivery

After pushing the verified commit, set the default token to read-only, disable
Action review approval, allow only GitHub-owned actions plus the two pinned
third-party action families, require SHA pinning, and protect `main` with both
firmware build contexts. Dispatch both workflows with release publication
enabled and verify their head SHA and state through the API.

## Verification

New regression scripts cover runtime migrations, root state safety, proxy
enablement, CoreMark parsing, variant metadata and workflow contracts. Existing
pinned-source tests, actionlint, ShellCheck, YAML parsing, action SHA checks and
diff review remain mandatory.
