#!/usr/bin/env bash

validate_experimental_manifest() {
  local manifest=$1 acceleration=$2 software=$3 package
  local -a required=()
  [ -s "$manifest" ] || return 1
  if grep -Eq '^(kmod-ath11k[^ ]*|ath11k-firmware[^ ]*|ipq-wifi-zn_m2|wpad[^ ]*|kmod-usb3|kmod-usb-dwc3[^ ]*) - ' "$manifest"; then
    echo 'Final package closure contains wireless or USB support' >&2; return 1
  fi
  case "$acceleration" in
    nss) required+=(kmod-qca-nss-drv kmod-qca-nss-ecm nss-firmware);;
    ppe|upstream-native) ;;
    *) return 1;;
  esac
  case "$software" in
    aurora-homeproxy) required+=(luci-app-homeproxy sing-box luci-theme-aurora);;
    upstream-native) required+=(fwxd kmod-fwx luci-theme-fanchmwrt);;
    *) return 1;;
  esac
  for package in "${required[@]}"; do
    grep -Eq "^$package - " "$manifest" || { echo "Required final package missing: $package" >&2; return 1; }
  done
}

validate_experimental_dtbs() {
  local tree=$1 acceleration=$2 dtb compatible node q6 nss count=0 address size
  local -a reg
  command -v fdtget >/dev/null || { echo 'fdtget required for final DTB validation' >&2; return 1; }
  while IFS= read -r -d '' dtb; do
    compatible=$(fdtget -t s "$dtb" / compatible 2>/dev/null) || continue
    [[ " $compatible " == *' zn,m2 '* ]] || continue
    q6=0; nss=0
    while IFS= read -r node; do
      read -r -a reg <<< "$(fdtget -t x "$dtb" "/reserved-memory/$node" reg 2>/dev/null || true)"
      case "${#reg[@]}" in
        4) address=${reg[1]}; size=${reg[3]};;
        2) address=${reg[0]}; size=${reg[1]};;
        *) continue;;
      esac
      if [ "$((16#$address))" -eq "$((0x4ab00000))" ]; then
        [ "$((16#$size))" -eq "$((0x1000000))" ] || { echo "Wrong Q6 reservation: $dtb" >&2; return 1; }
        q6=1
      fi
      if [ "$((16#$address))" -eq "$((0x40000000))" ]; then
        case "$acceleration" in
          nss|upstream-native) [ "$((16#$size))" -eq "$((0x1000000))" ] || { echo "NSS/platform reservation lost: $dtb" >&2; return 1; };;
          ppe) [ "$((16#$size))" -eq 0 ] || return 1;;
          *) return 1;;
        esac
        nss=1
      fi
    done < <(fdtget -l "$dtb" /reserved-memory)
    [ "$q6" -eq 1 ] && [ "$nss" -eq 1 ] || { echo "Missing platform reservations: $dtb" >&2; return 1; }
    count=$((count + 1))
    printf 'Validated final DTB: %s\n' "$dtb"
  done < <(find "$tree/build_dir" -type f -name '*m2*.dtb' -print0)
  [ "$count" -gt 0 ] || { echo 'No compiled ZN-M2 DTB found' >&2; return 1; }
}
