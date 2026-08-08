# ZN-M2 DHCP Boot Guard Design

## Problem

On the verified 256M main-router image, the `dhcp.lan` UCI section enables an
IPv4 DHCP server, but the running dnsmasq instance has no generated
`dhcp-range` and no UDP/67 socket. Static-address LAN access still works. The
pinned dnsmasq init script starts before networking and omits DHCP range
generation during boot, expecting a later interface event to reload dnsmasq.
That reload did not occur on the observed device. The existing healthcheck
cannot detect the failure because it only checks DNS after a default route is
present, and DNS remains healthy on UDP/53.

## Scope

Add a ZN-M2 runtime guard around the existing healthcheck. Do not patch the
pinned upstream dnsmasq package, change administrator DHCP policy, introduce a
daemon, or add fixed boot delays. Preserve all sysupgrade configuration
behavior.

## Runtime Detection

The guard considers LAN DHCP intentionally disabled when
`dhcp.lan.ignore=1` or `dhcp.lan.dhcpv4=disabled`. Otherwise it requires both:

- an active `dhcp-range` line in a generated dnsmasq configuration file; and
- an IPv4 or IPv6 UDP socket whose local port is hexadecimal `0043` (67).

The generated-config glob and proc paths are injectable for regression tests.
Requiring both signals avoids treating a stale generated file or a DNS-only
dnsmasq process as healthy.

## Recovery

Run DHCP validation before the default-route gate, so WAN state cannot suppress
LAN recovery. When DHCP is enabled but unhealthy, log the missing runtime
state and request one dnsmasq restart through the existing atomic cooldown
mechanism. Recheck immediately after the synchronous init-script command and
log either recovery or continuing failure. A cooldown denial performs no
restart, preventing cron or hotplug loops.

Add a small `/etc/hotplug.d/iface` hook that invokes the healthcheck in
DHCP-only mode when logical interface `lan` reports `ifup`. Periodic cron runs
remain a fallback. The hook does not sleep and does not run DNS, proxy, or WAN
checks.

## Testing

Shell regression tests use real healthcheck control flow with injected UCI,
generated-config, proc-UDP, logger, and init-script fixtures. They cover:

- enabled DHCP with missing range/socket restarts dnsmasq once;
- healthy DHCP does not restart dnsmasq;
- intentionally disabled DHCP does not restart dnsmasq;
- missing WAN/default route does not suppress DHCP checking;
- cooldown state prevents repeated restarts;
- post-restart success and failure are logged;
- the LAN hotplug hook invokes DHCP-only mode and ignores unrelated events;
- existing config-preserving upgrade tests remain unchanged and pass.

## Operational Safety

Device validation must bind traffic to the wired host address because the test
host has overlapping Ethernet and Wi-Fi `192.168.1.0/24` networks that reach
different routers. Enabling DHCP on the Windows Ethernet test adapter is out of
scope; retain the static, gateway-free test address.
