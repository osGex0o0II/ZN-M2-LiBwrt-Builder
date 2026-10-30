# ZN-M2 Multi-Upstream Implementation Plan

> For agentic workers: use subagent-driven-development; execute continuously with task review. Already authorized by user; no new design approval required.

**Goal:** source-neutral ZN-M2 256M wired firmware builder with distinct PPE/NSS profiles, VIKING main and LEDE integrations, and native hardware port in the user's FanchmWrt fork.
**Architecture:** profile identities + upstream adapters + acceleration policy + upstream software selection; shared CI/packaging without copying five mature pipelines.
**Tech Stack:** POSIX shell/Bash, OpenWrt Make/DTS/Kconfig, GitHub Actions.
**Spec:** docs/history/specs/2026-10-29-zn-m2-multi-upstream.md

## Global Constraints
Preserve untracked device data, unrelated PR64 and old releases. Stock256M, wired-only, noUSB. Existing variants retain Aurora/HomeProxy; Fanch UI/FWX retained. NSS reserved-memory never zeroed. Full-firmware and device results are separate gates. No main push/merge or stable publication by implication.

## Task 1: Existing profiles and PPE migration
- [ ] Run existing fixture regression tests before modification.
- [ ] Add behavior tests proving NSS policy cannot leak into PPE/upstream-native policy, profile identity distinguishes VIKING owrt/main, and artifact/retention selection does not cross variants. Observe expected failures.
- [ ] Implement explicit profile metadata and loader/policy interfaces; update mature workflows, source manifests, PPE assets and docs. Preserve legacy required-check compatibility until remote migration. Refactor repeated CI pieces only behind executable interfaces.
- [ ] Run all affected fixture/workflow tests, shell syntax, YAML validation. Record failures and commands. Review complete diff.

## Task 2: VIKING main NSS
- [ ] Inspect fixed main SHA and actual qca-nss Kconfig/DTS/feed layout; save source fixtures outside tracked tree.
- [ ] Test adapter fixture for idempotence, 256M wired removals, retained NSS region, missing-source rejection. Observe failures.
- [ ] Add independent config/pins/adapter using existing NSS software profile; manual experimental CI through shared mechanism, not duplicated giant workflow.
- [ ] Verify source fixture and defconfig where toolchain available, then full-firmware CI on review branch. Review before declaring source integration ready.

## Task 3: LEDE
- [ ] Inspect native zn_m2 image definition, ipq6018 DTS include chain, network and NAND upgrade scripts at fixed SHA.
- [ ] Add adapter regression fixture covering exact zn,m2 LAN/WAN and NAND branch insertion, idempotence and unrelated boards retained. Observe failures.
- [ ] Add independent source pins/config/adapter preserving Aurora/HomeProxy selection through upstream-compatible feeds; default6.12.114 verified source.
- [ ] Run fixture and source validation; experimental build; review.

## Task 4: FanchmWrt fork hardware port
- [ ] Check user's fork permissions/default SHA; clone to dedicated checkout. Preserve upstream tracking branch; use codex feature branch.
- [ ] Inspect SoC support, NAND layout/current known ZN-M2 DTS and board scripts. Define source-supported port with tests of generated device profile, network/LED/sysupgrade handlers and DT compile or equivalent upstream build check.
- [ ] Add minimal native ZN-M2 hardware support in fork, keep upstream UI/FWX/default services and no arbitrary NSS label; commit reviewable changes.
- [ ] Add builder profile pointing at exact fork commit and own feed pin. Share only hardware contracts/diagnostics; do not overlay Aurora/HomeProxy choices.
- [ ] Run tests/build checks. Open review branches/PRs when ready; no source main merge or publication.

## Task 5: Integration and handoff
- [ ] Full shell/workflow/profile tests; use actionlint and real source probes. Inspect every diff and final reviewer findings.
- [ ] Preserve required check contexts or coordinate PPE rename using tested PR checks; never leave protection waiting on absent check.
- [ ] Update source-neutral title/docs and status table with actual validation levels. Repository remote rename deferred until build/link migration verified.
- [ ] Report branches/commits/build URLs and explicit device-validation gaps; do not mark experimental firmware stable.
