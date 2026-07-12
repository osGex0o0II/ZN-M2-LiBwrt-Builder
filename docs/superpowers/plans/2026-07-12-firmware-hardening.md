# Firmware Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix every actionable two-variant audit finding, push the verified result to main, harden repository policy, and start both release builds.

**Architecture:** Keep runtime migrations in variant-scoped uci-default scripts, keep healthcheck state handling self-contained, and encode firmware invariants as executable shell tests plus workflow gates. Apply repository policy only after the verified main push.

**Tech Stack:** POSIX shell, Bash, OpenWrt UCI, GitHub Actions YAML, GitHub REST API, git.

---

### Task 1: Runtime and upgrade safety

**Files:** create `tests/test-runtime-hardening.sh`, `files/etc/uci-defaults/95-upgrade-security-migration.sh`, `files-256m/etc/uci-defaults/95-upgrade-dns-migration.sh`; modify healthcheck, CoreMark, and uci-default regression tests.

- [ ] Write fixtures for the exact old root hash, missing IPv6 rules, old DNS tuple, unconfigured/configured HomeProxy, hostile state symlink, failed/successful CoreMark.
- [ ] Run `sh tests/test-runtime-hardening.sh`; expect failure against current behavior.
- [ ] Implement exact-match migrations, root-owned atomic state, functional proxy predicate and strict benchmark parsing.
- [ ] Run runtime and existing uci-default tests; expect PASS.

### Task 2: Variant and package contracts

**Files:** create `tests/test-variant-contracts.sh`; modify `libwrt.sh` and `configs/zn-m2-1g-proxygateway.config`.

- [ ] Assert pinned-feed sing-box conflict/provide shape and explicit 1G no-initramfs/IPQ1024/NSS MEDIUM/NSS+ECM settings.
- [ ] Run the new test; expect failure.
- [ ] Align sing-box metadata and add explicit 1G settings.
- [ ] Re-run the new and existing tests; expect PASS.

### Task 3: Workflow integrity and performance

**Files:** create `tests/test-workflow-contracts.sh`; modify both firmware workflows and auto-merge workflow.

- [ ] Assert no bare negative gates, stable cache keys, compile timeout/no serial retry, release-only artifact upload, defconfig diagnostic check, 1G manifest/profile checks, paginated non-critical cleanup, and no action-PR auto-merge.
- [ ] Run the new test; expect failure.
- [ ] Implement the workflow changes and preserve pinned action SHAs.
- [ ] Run workflow contracts, YAML parsing and actionlint; expect PASS.

### Task 4: Full verification and delivery

**Files:** all changed files.

- [ ] Run every repository test with pinned source/feed fixtures where required, shell syntax, ShellCheck, YAML, actionlint, action pin and diff checks.
- [ ] Review the complete diff for upgrade safety and 256M regression.
- [ ] Commit atomic groups using the repository's imperative message style and push `main`.
- [ ] Apply Actions restrictions and main protection through authenticated GitHub API, then read them back.
- [ ] Dispatch both firmware workflows with `firmware_release=true`; verify run head SHA and state.
- [ ] Remove QA resources and confirm clean worktree.
