# ZN-M2 LiBwrt 6.12 NSS Build

This repository is a single-device GitHub Actions build for the ZN-M2
IPQ60xx router. It targets LiBwrt `openwrt-6.x` `main-nss` and keeps the image
wired-only, storage-free, and focused on HomeProxy with sing-box.

## Build Target

- Device: ZN-M2 (`qualcommax/ipq60xx/zn_m2`)
- Source: <https://github.com/LiBwrt/openwrt-6.x.git>
- Branch: `main-nss`
- Config: `configs/zn-m2.config`
- Custom script: `libwrt.sh`
- Workflow: `.github/workflows/ZN-M2.yml`
- Release tag: `ZN-M2-6.12-NSS`

## Included Focus

- Qualcomm NSS acceleration options for the `main-nss` branch
- HomeProxy from ImmortalWrt `homeproxy`, replacing older feed copies
- `sing-box`
- TTYD service and LuCI web console
- Aurora theme, Simplified Chinese LuCI, hostname `ZN-M2`
- BBR and basic network tuning
- WiFi and storage-related packages disabled

## Build

Open GitHub Actions, run the `ZN-M2` workflow manually, and download the
firmware from the `ZN-M2-6.12-NSS` release after the build completes.

Default login after flashing:

- Address: `192.168.1.1`
- User: `root`
- Password: `password`
