# ZN-M2 LiBwrt 6.12 NSS Builds

This repository builds wired-only LiBwrt `openwrt-6.x` `main-nss` firmware for
ZN-M2. It now has two separate variants for the upgraded 1G RAM unit and the
original 128M RAM unit.

推送测试成功

## Variants

- 1G HomeProxy: `.github/workflows/ZN-M2-1G-HomeProxy.yml`
  - Config: `configs/zn-m2-1g-homeproxy.config`
  - Release tag: `ZN-M2-1G-6.12-NSS-HomeProxy`
  - Includes HomeProxy and sing-box.
- 128M Performance: `.github/workflows/ZN-M2-128M-Performance.yml`
  - Config: `configs/zn-m2-128m-performance.config`
  - Release tag: `ZN-M2-128M-6.12-NSS-Performance`
  - Removes proxy and web terminal packages, keeps Aurora and performance tuning.

Both variants target:

- Qualcomm NSS acceleration options for the `main-nss` branch
- Aurora theme, Simplified Chinese LuCI, hostname `ZN-M2`
- BBR and basic network tuning
- WiFi and storage-related packages disabled

## Build

Open GitHub Actions, run the workflow for the variant you need, and download
firmware from the matching release tag after the build completes.

Default login after flashing:

- Address: `192.168.1.1`
- User: `root`
- Password: `password`
