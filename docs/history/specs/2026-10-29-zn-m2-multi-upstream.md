# ZN-M2 multi-upstream design

Approved in conversation 2026-10-29: implement prior staged recommendation; preserve each upstream software identity. Public layer unifies hardware behavior and basic diagnostics. FanchmWrt keeps its UI/FWX; existing variants may retain Aurora/HomeProxy. Target remains stock 256M, wired-only, no USB. No performance claims or stable releases without hardware evidence.

Source ownership: FanchmWrt hardware support belongs in osGex0o0II/FanchmWrt fork. Builder owns profile/pins/customization/CI. Never duplicate a board patch in both. Existing open PR64 is unrelated and preserved; work starts a757a09 on isolated codex branch.

Architecture: explicit source/branch/acceleration profile identity; per-upstream adapters; separate acceleration runtime policy and reserved-memory; shared packaging/validation/diagnostics and CI orchestration where interfaces are proven. Existing two mature pipelines can migrate incrementally, but no five copied 800-line workflows. Experimental additions manual/artifact-only until validated. Kernel detected from source, never inferred from profile ID.

Migration: No NSS -> PPE across docs/CI/artifacts/config paths where useful; required GitHub check-name compatibility must be maintained until an atomic protection-rule migration is possible. Keep old public releases/assets immutable. Cache grouping uses profile identity instead of kernel alone. Full source/pin/config/builder provenance in manifest.

NSS must retain NSS reserved-memory; PPE zero-sizing cannot reach NSS. Do not blindly enable PPE hardware offload without testing nft/driver behavior and proxy compatibility. Existing behavior conservative until supported by evidence; provide diagnostic status without claiming acceleration active.

Sequence: establish existing baselines and naming/policy separation -> VIKING main NSS -> LEDE master default6.12 NSS and board-script fixes -> FanchmWrt fork port and builder integration. Fanch UI/FWX native feeds retained.

Validation levels: source/static; defconfig+DTB+package build; full firmware CI; device boot/network/upgrade; runtime acceleration+memory soak. Record each honestly. No flashing devices without a selected device/recovery context.
