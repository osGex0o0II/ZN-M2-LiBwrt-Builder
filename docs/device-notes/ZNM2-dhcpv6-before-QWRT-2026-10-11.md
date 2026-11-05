# ZNM2 DHCPv6 Baseline Before QWRT Comparison

Captured: 2026-10-10 18:27 UTC (2026-10-11 02:27 Asia/Shanghai)
Router: 10.0.0.1
Purpose: Preserve the ZNM2 DHCPv6 state before the user switches to QWRT, for a same-port packet-level comparison.

## Device and firmware

- Model: ZN M2 (`board_name=zn,m2`)
- Distribution/version: LibWrt 25.12-SNAPSHOT
- Revision: `r0-3a3d0b0`
- Target: `qualcommax/ipq60xx`; kernel `6.12.108`; ARMv8
- Runtime memory was previously measured as 180,428,800 bytes, consistent with the 256M profile.
- SSH host fingerprint: `SHA256:CSlUwL4jbmaVVljmqZ5X7gJRaiuiIHBp9C7h0Fc3LXY`

## Relevant configuration

- `network.wan6.proto=dhcpv6`
- `network.wan6.device=wan`
- `network.wan6.reqaddress=try`
- `network.wan6.reqprefix=auto`
- `network.lan.ip6assign=64`
- `dhcp.lan.ra=hybrid`
- `dhcp.lan.dhcpv6=relay`
- `dhcp.lan.ndp=relay`
- `dhcp.lan.force=1`
- Configured client DUID SHA-256: `61917c0412b4ce3986b6f2c1ad83775ba0a1843bb5848d736233725fab4fb226` (raw DUID intentionally omitted).

## Runtime state at capture

- `wan6`: up, `proto=dhcpv6`, delegation enabled; one RA/SLAAC global IPv6 address with `/64`, default route and DNS present.
- `wan6.ipv6-prefix=[]`; `wan6.ipv6-prefix-assignment=[]`.
- `lan`: up on `br-lan`; no IPv6 address, delegated prefix or prefix assignment.
- DHCPv6 counters after the controlled exchange: Solicit=1, Advertise=1, Request=0, Reply=1, Information-request=1, discarded=0, transmit failures=0.
- odhcp6c state: `BOUND_PROCESSING`; `PREFIXES=[]`; `ADDRESSES=[]`; RA address/route/DNS populated.

## Captured DHCPv6 exchange

One bounded tcpdump capture was taken on `wan` while `wan6` was reconnected once. Four packets were captured, zero dropped.

- ZNM2 Solicit included both IA_NA and IA_PD (IAID `3160834241`); the client ID was DUID-UUID.
- Matching upstream Advertise returned `NoAddrsAvail` inside IA_NA and `NoPrefixAvail` inside IA_PD. The outer message status was Success; the server preference was 255.
- No Request followed because the Advertise offered neither an address nor a delegated prefix.
- The separate Information-request received a Reply with DNS information and lifetime 86400.
- Interpretation: ZNM2 is requesting PD; upstream DHCPv6 responds that no prefix is available for this IA_PD. WAN IPv6 is independently supplied through RA/SLAAC. This capture alone does not identify why QWRT receives a different result.

## Comparison targets for QWRT

Using the same cable and physical port, compare:

1. Server Identifier and server source/link-local endpoint, to confirm the same DHCPv6 server/relay answered.
2. Client Identifier DUID (record only its type and a hash), IAIDs, and whether both IA_NA and IA_PD are requested.
3. Option Request list, Vendor Class/User Class, Client-FQDN, prefix hints, and other DHCPv6 options.
4. Advertise/Reply status codes and whether a prefix is offered, then whether the client sends Request.

The repeated IAID value across IA_NA and IA_PD is not by itself evidence of a defect: the IAID spaces are scoped separately by IA type, and this OpenWrt configuration uses the same generated interface IAID for both.

## Changes during this check

- No router configuration or firmware was changed.
- `wan6` was reconnected once for the capture and is currently up.
- Temporary `tcpdump-mini` and `libpcap1` were installed under an apk virtual package and removed after capture; package index cache and capture file were deleted. `tcpdump` is absent now.
- Existing unrelated untracked workspace directories were left untouched.
