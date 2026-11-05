# QWRT DHCPv6 State After Switch

Captured: 2026-10-10 18:27 UTC (2026-10-11 02:27 Asia/Shanghai)
Router: 10.0.0.1
Purpose: Record QWRT runtime state for comparison with `ZNM2-dhcpv6-before-QWRT-2026-10-11.md`.

## Device and firmware

- Model: JDCloud AX1800 Pro (`board_name=jdcloud,ax1800-pro`), hostname `QWRT`
- Distribution/version: QWRT 25.12.2
- Revision: `R26.10.6 (QSDK 12.5)`
- Target: `ipq60xx/generic`; kernel `5.4.213`; ARMv8
- SSH host fingerprint observed after firmware switch: `SHA256:yLhFPJcXKghan6Y1UFWYdilO81N/WLtX2AxEJGfx3Zw`

## Relevant configuration and client process

- `network.wan6.proto=dhcpv6`
- `network.wan6.device=eth3`
- `network.wan6.reqaddress` and `network.wan6.reqprefix` are unset in UCI.
- Running client: `odhcp6c -s /lib/netifd/dhcpv6.script -P0 -t120 eth3`; `-P0` requests an automatic delegated prefix.
- `network.globals.dhcp_default_duid` is unset; packet capture shows on-wire client DUID-LL (Ethernet hardware type 1). SHA-256 of the normalized on-wire DUID: `1f5d240093531272e16766f72c4a954f9d96daf89ae080653330413705e4bf99` (raw identifier omitted).
- `network.lan.ip6assign=60`
- `dhcp.lan.ra=server`; `dhcp.lan.dhcpv6=server`; `dhcp.lan.force=1`; `dhcp.lan.ndp` is unset.

## Runtime state

- `wan6`: up on `eth3`; one RA/SLAAC WAN address `/64`; one delegated prefix `/64`; default route and DNS present.
- The delegated prefix is assigned to LAN by netifd.
- `lan`: up on `br-lan`; LAN DHCP/RA server mode.
- QWRT's `odhcp6c.wan` ubus statistics object was not found; no transaction counters were available from that endpoint.
- A temporary compatible tcpdump capture was made on `eth3` during one `wan6` reconnect: 8 packets captured, 0 dropped.

## Captured DHCPv6 exchange

- QWRT first sent DHCPv6 Release for its previous IA_PD. The server returned Reply with outer `Success`.
- QWRT SOLICIT requested both IA_NA and IA_PD, with IAID `1` for each. The server ADVERTISE returned `NoAddrsAvail` inside IA_NA, but offered a `/64` IA_PD with status `Success`; outer status was also `Success`, preference `255`.
- A subsequent SOLICIT requested IA_PD; the server offered a `/64` prefix. QWRT sent REQUEST and received REPLY with IA_PD status `Success`.
- Captured QWRT client ID is DUID-LL, hardware type 1 (Ethernet); server ID is DUID-LLT, hardware type 1. Server source was link-local `fe80::1`. Raw identifiers and global IPv6 addresses are intentionally omitted.
- The decoded SOLICIT had no Vendor Class or User Class; it included Client-FQDN and Reconfigure-Accept. IA_NA was not successfully assigned.
- Post-capture `ifstatus wan6`: `up=true`, `delegation=true`, one delegated `/64` assigned to LAN.

## Controlled DUID test

- On the same QWRT firmware, `eth3`, cable, and WAN settings, temporarily set only `network.wan6.clientid` to a newly generated valid DUID-UUID (type 4), then reloaded the network. The raw test DUID was not retained.
- With DUID type 4, QWRT still sent IA_PD SOLICITs, but the server returned `NoPrefixAvail` twice; `ifstatus wan6` showed zero delegated prefixes. This rules out the client simply failing to request PD.
- Deleted the temporary UCI `clientid` override and reloaded the network. With the original automatically generated DUID-LL restored, the server again offered a `/64`; QWRT completed REQUEST/REPLY with IA_PD `Success`. Post-test `wan6` was up with one delegated prefix.
- This is a same-device toggle proof that changing the DHCPv6 client DUID changes the upstream PD result. The ISP is applying a DUID-dependent lease/allocation policy; this test cannot separate a policy keyed on DUID type from a policy keyed on the exact DUID value.
- The ZNM2 raw DUID was intentionally not retained, so the generated UUID used here is not an exact byte-for-byte replay of ZNM2's identifier. An exact replay would be needed to prove the ISP's specific ZNM2 binding.

## Comparison with ZNM2 baseline

- ZNM2: `wan6.device=wan`, explicit `reqprefix=auto`, DUID-UUID, LAN `ip6assign=64`, RA/DHCPv6 relay mode, no PD; its Advertise returned `NoPrefixAvail` for IA_PD.
- QWRT: `wan6.device=eth3`, `reqprefix` unset but running client uses `-P0`, DUID-LL, LAN `ip6assign=60`, RA/DHCPv6 server mode; its Advertise/Reply granted and installed a `/64` PD.
- Both clients request automatic PD, so failure to request PD is ruled out. Different DUID types are the strongest confirmed client-side discriminator correlated with the different server response. Upstream DUID-based lease/profile selection is a leading explanation, but its policy cannot be proven without a controlled same-DUID test or ISP-side logs. LAN relay/server mode and `ip6assign` affect downstream distribution, not the observed WAN Advertise status.

## Logs at capture

- Early boot logs included transient `Failed to send RS` and DHCPv6 network/address unavailable errors while the interface was initializing.
- Later logs show the interface became up and odhcp6c received outer message status `success`.

## Current tool state

- No permanent QWRT UCI/network configuration was changed. The temporary `network.wan6.clientid` control value was deleted and committed; original automatic DUID behavior is restored. `wan6` is up with delegated `/64` assigned to LAN.
- QWRT feeds supplied incompatible `tcpdump-mini 4.99.5-r1`; temporary official `tcpdump-mini 4.9.3-4` was used with pre-existing `libpcap1 1.9.1-2.1`, without changing the library. Afterwards, `tcpdump-mini` and `/tmp` package/capture files were removed; `libpcap1` remains `1.9.1-2.1`, and `tcpdump` is absent.
- Overlay had 1,823,764 KiB available and `/tmp` had 461,884 KiB available.
