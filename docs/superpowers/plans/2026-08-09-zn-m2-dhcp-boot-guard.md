# ZN-M2 DHCP Boot Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect and recover the ZN-M2 boot state where LAN DHCP is enabled in UCI but dnsmasq has no active DHCP range or UDP/67 listener.

**Architecture:** Extend the existing common healthcheck with an independently executed DHCP check and reuse its atomic cooldown for a single bounded dnsmasq restart. Trigger that same check from a LAN-ifup hotplug hook for prompt boot recovery while retaining cron as fallback.

**Tech Stack:** POSIX shell, OpenWrt UCI, dnsmasq generated configuration, Linux procfs, netifd hotplug.

## Global Constraints

- Do not patch upstream dnsmasq or change administrator UCI policy.
- Do not use fixed boot sleeps or introduce a persistent daemon.
- Preserve config-restored/sysupgrade behavior.
- Recovery must be bounded by the existing cooldown state.

---

### Task 1: DHCP runtime regression coverage

**Files:**
- Modify: `tests/test-healthcheck-hardening.sh`

**Interfaces:**
- Consumes: `STATE_DIR`, `STATE_OWNER`, `INIT_DIR`, and `ZN_M2_PATH` healthcheck injection points.
- Produces: fixtures for `DNSMASQ_CONFIG_GLOB`, `PROC_NET_UDP`, and `PROC_NET_UDP6`, plus assertions for restart and logging behavior.

- [ ] **Step 1: Add failing behavioral fixtures**

Extend the mock `uci` command with `dhcp.lan.ignore` and
`dhcp.lan.dhcpv4`, add generated dnsmasq and proc-UDP fixtures, and add a mock
dnsmasq init script. Run independent cases for unhealthy, healthy, disabled,
no-default-route, cooldown, and post-restart logging states.

- [ ] **Step 2: Verify RED**

Run: `sh tests/test-healthcheck-hardening.sh`

Expected: FAIL because the current healthcheck never inspects the DHCP runtime
and never restarts dnsmasq when local DNS still resolves.

### Task 2: Bounded DHCP guard

**Files:**
- Modify: `files/usr/sbin/zn-m2-healthcheck`

**Interfaces:**
- Consumes: `uci -q get dhcp.lan.ignore`, `uci -q get dhcp.lan.dhcpv4`, generated dnsmasq configs, and `/proc/net/udp{,6}`.
- Produces: `check_dhcp`, `dhcp_runtime_healthy`, and the `--dhcp-only` command mode.

- [ ] **Step 1: Implement the minimum enabled-state and runtime checks**

Treat `ignore=1` or `dhcpv4=disabled` as an intentional disable. Otherwise,
require an uncommented `dhcp-range=` and a procfs local port `0043` socket.

- [ ] **Step 2: Implement bounded recovery and recheck**

Call `restart_service dnsmasq` only after an unhealthy result, preserve the
existing cooldown, then log `lan dhcp recovered` or
`lan dhcp remains unavailable after dnsmasq restart` based on the recheck.
Execute `check_dhcp` before `has_default_route`; make `--dhcp-only` exit after
that check.

- [ ] **Step 3: Verify GREEN**

Run: `sh tests/test-healthcheck-hardening.sh`

Expected: `healthcheck hardening regression tests passed` with exit code 0.

### Task 3: LAN-ifup trigger

**Files:**
- Create: `files/etc/hotplug.d/iface/99-zn-m2-dhcp-guard`
- Modify: `tests/test-healthcheck-hardening.sh`

**Interfaces:**
- Consumes: netifd `ACTION` and `INTERFACE` environment variables.
- Produces: `/usr/sbin/zn-m2-healthcheck --dhcp-only` invocation for `ACTION=ifup INTERFACE=lan` only.

- [ ] **Step 1: Add the failing hook contract test**

Execute a fixture copy of the hook for LAN ifup, LAN ifdown, and WAN ifup;
assert exactly one `--dhcp-only` invocation.

- [ ] **Step 2: Verify RED**

Run: `sh tests/test-healthcheck-hardening.sh`

Expected: FAIL because the hook does not exist.

- [ ] **Step 3: Add the minimal hook**

Guard on `ACTION=ifup` and `INTERFACE=lan`, verify the healthcheck is
executable, and invoke it with `--dhcp-only` while redirecting output.

- [ ] **Step 4: Verify GREEN**

Run: `sh tests/test-healthcheck-hardening.sh`

Expected: PASS with exactly one hook invocation.

### Task 4: Full regression verification

**Files:** all changed files.

**Interfaces:**
- Consumes: repository test suite and shell parsers.
- Produces: verification evidence for behavior, syntax, upgrade preservation, and complete diff scope.

- [ ] **Step 1: Run focused syntax and behavior checks**

Run `sh -n files/usr/sbin/zn-m2-healthcheck files/etc/hotplug.d/iface/99-zn-m2-dhcp-guard tests/test-healthcheck-hardening.sh` and `sh tests/test-healthcheck-hardening.sh`; expect exit code 0.

- [ ] **Step 2: Run upgrade and UCI regressions**

Run `sh tests/test-upgrade-migrations.sh` and `sh tests/test-uci-defaults.sh`; expect both to pass without changes to preserved administrator DHCP policy.

- [ ] **Step 3: Run the complete repository shell test suite**

Run every `tests/test-*.sh`; expect zero failures.

- [ ] **Step 4: Review diff and status**

Use `git diff --check`, `git diff`, and `git status --short`; confirm only the design, plan, healthcheck, hotplug hook, and focused test changes are part of this repair.
