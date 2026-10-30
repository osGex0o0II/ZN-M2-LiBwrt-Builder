#!/usr/bin/env bash
set -euo pipefail
EXPERIMENTAL_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

valid_revision() { [[ "$1" =~ ^[0-9a-f]{40}$ ]]; }

load_experimental_profile() {
  local metadata key value
  metadata=$(bash "$EXPERIMENTAL_ROOT/scripts/load-profile.sh" "$1")
  while IFS='=' read -r key value; do
    case "$key" in PROFILE_ID|SOURCE_REPO|SOURCE_BRANCH|SOURCE_PINS|PROFILE_CONFIG|PROFILE_ADAPTER|ACCELERATION_POLICY|SOFTWARE_POLICY|CACHE_NAMESPACE) export "$key=$value";; *) return 1;; esac
  done <<< "$metadata"
  set -a
  source "$EXPERIMENTAL_ROOT/$SOURCE_PINS"
  set +a
  valid_revision "$OPENWRT_COMMIT" || { echo 'Invalid source revision' >&2; return 1; }
}

pin_native_feeds() {
  local tree=$1 type name location extra key revision base count=0
  local output="$1/feeds.conf.builder.tmp"
  : > "$output" || return 1
  while read -r type name location extra; do
    case "$type" in ''|\#*) continue;; src-git|src-git-full) ;; *) echo "Unsupported feed type: $type" >&2; return 1;; esac
    [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] && [ -z "$extra" ] || return 1
    key="FEED_${name^^}_COMMIT"; key=${key//-/_}
    revision=${!key:-}
    if [ -z "$revision" ] && [[ "$location" == *^* ]]; then revision=${location##*^}; fi
    valid_revision "$revision" || { echo "Missing fixed revision: $name" >&2; return 1; }
    base=${location%%^*}; base=${base%%;*}
    [[ "$base" == https://* ]] || return 1
    printf '%s %s %s^%s\n' "$type" "$name" "$base" "$revision" >> "$output" || return 1
    count=$((count + 1))
  done < "$tree/feeds.conf.default"
  [ "$count" -gt 0 ] || return 1
  if [ "$SOFTWARE_POLICY" = aurora-homeproxy ]; then
    valid_revision "${VIKINGYFY_COMMIT:-}" || return 1
    printf 'src-git vikingfy https://github.com/VIKINGYFY/packages.git^%s\n' "$VIKINGYFY_COMMIT" >> "$output" || return 1
  fi
  mv "$output" "$tree/feeds.conf" || return 1
}

stage_profile_files() {
  local tree=$1
  mkdir -p "$tree/files/etc" "$tree/files/usr/sbin" || return 1
  case "$SOFTWARE_POLICY" in
    aurora-homeproxy)
      cp -a "$EXPERIMENTAL_ROOT/files/." "$tree/files/" || return 1
      cp -a "$EXPERIMENTAL_ROOT/files-zn-m2/." "$tree/files/" || return 1
      ;;
    upstream-native)
      # Diagnostics only: preserve FanchmWrt theme, FWX, service and UCI defaults.
      cp "$EXPERIMENTAL_ROOT/files/usr/sbin/zn-m2-diagnostics" "$tree/files/usr/sbin/" || return 1
      chmod +x "$tree/files/usr/sbin/zn-m2-diagnostics" || return 1
      ;;
    *) return 1;;
  esac
  printf '%s\n' "$ACCELERATION_POLICY" > "$tree/files/etc/zn-m2-acceleration-policy" || return 1
  printf 'profile=%s\nacceleration_policy=%s\nsoftware_policy=%s\nvalidation=experimental\n' "$PROFILE_ID" "$ACCELERATION_POLICY" "$SOFTWARE_POLICY" > "$tree/files/etc/zn-m2-build-profile" || return 1
}

apply_software_policy() (
  local tree=$1 path
  [ "$SOFTWARE_POLICY" = aurora-homeproxy ] || return 0
  valid_revision "$AURORA_COMMIT"
  cd "$tree"
  [ ! -e package/luci-theme-aurora ] || { echo 'Aurora path already exists' >&2; return 1; }
  git init package/luci-theme-aurora
  git -C package/luci-theme-aurora remote add origin https://github.com/eamonxg/luci-theme-aurora.git
  git -C package/luci-theme-aurora fetch --depth=1 origin "$AURORA_COMMIT"
  git -C package/luci-theme-aurora checkout --detach FETCH_HEAD
  for path in package/luci-app-homeproxy package/network/services/sing-box package/feeds/luci/luci-app-homeproxy package/feeds/packages/sing-box package/feeds/packages/sing-box-tiny; do
    rm -rf -- "$path"
  done
  ./scripts/feeds install -f -p vikingfy luci-app-homeproxy sing-box
)

verify_resolved_config() {
  local tree=$1
  grep -Eq '^CONFIG_TARGET_(DEVICE_)?qualcommax_ipq60xx(_DEVICE_zn_m2)?=y$' "$tree/.config"
  grep -Eq '^CONFIG_TARGET_(DEVICE_)?qualcommax_ipq60xx_DEVICE_zn_m2=y$' "$tree/.config"
  grep -Fxq 'CONFIG_TARGET_ROOTFS_SQUASHFS=y' "$tree/.config"
  if grep -Eq '^CONFIG_PACKAGE_(kmod-ath11k[^=]*|ath11k-firmware[^=]*|wpad[^=]*|kmod-usb3|kmod-usb-dwc3[^=]*)=y$' "$tree/.config"; then
    echo 'Resolved config re-enabled wireless/USB' >&2; return 1
  fi
  if [ "$ACCELERATION_POLICY" = nss ]; then
    grep -Fxq 'CONFIG_PACKAGE_kmod-qca-nss-drv=y' "$tree/.config"
    grep -Fxq 'CONFIG_PACKAGE_kmod-qca-nss-ecm=y' "$tree/.config"
  fi
  if [ "$SOFTWARE_POLICY" = aurora-homeproxy ]; then
    grep -Fxq 'CONFIG_PACKAGE_luci-app-homeproxy=y' "$tree/.config"
    grep -Fxq 'CONFIG_PACKAGE_sing-box=y' "$tree/.config"
    grep -Fxq 'CONFIG_PACKAGE_luci-theme-aurora=y' "$tree/.config"
  else
    grep -Fxq 'CONFIG_PACKAGE_fwxd=y' "$tree/.config"
    grep -Fxq 'CONFIG_PACKAGE_kmod-fwx=y' "$tree/.config"
    grep -Fxq 'CONFIG_PACKAGE_luci-theme-fanchmwrt=y' "$tree/.config"
  fi
}

write_build_provenance() {
  local tree=$1 branch kernel_file
  branch=$(sed -n 's/^KERNEL_PATCHVER:=//p' "$tree/target/linux/qualcommax/Makefile" | tr -d '\r ')
  kernel_file="$tree/target/linux/generic/kernel-$branch"
  [ -f "$kernel_file" ] || kernel_file="$tree/include/kernel-$branch"
  EXPERIMENTAL_KERNEL="$branch$(sed -n "s/^LINUX_VERSION-$branch[[:space:]]*=[[:space:]]*//p" "$kernel_file" | tr -d '\r ')"
  {
    printf 'Profile: %s\nSource: %s\nBranch: %s\nSource commit: %s\nKernel: %s\n' "$PROFILE_ID" "$SOURCE_REPO" "$SOURCE_BRANCH" "$OPENWRT_COMMIT" "$EXPERIMENTAL_KERNEL"
    printf 'Builder commit: %s\nAcceleration policy: %s\nSoftware policy: %s\n' "$(git -C "$EXPERIMENTAL_ROOT" rev-parse HEAD)" "$ACCELERATION_POLICY" "$SOFTWARE_POLICY"
    printf 'Validation: experimental; device validation pending\nRun: %s\n' "${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-local}/actions/runs/${GITHUB_RUN_ID:-local}"
    sha256sum "$EXPERIMENTAL_ROOT/$PROFILE_CONFIG" "$EXPERIMENTAL_ROOT/$PROFILE_ADAPTER" "$tree/.config"
    cat "$EXPERIMENTAL_ROOT/$SOURCE_PINS" "$tree/feeds.conf"
  } > "$tree/BUILD-MANIFEST.txt"
  printf '%s\n' "$EXPERIMENTAL_KERNEL" > "$tree/.builder-kernel"
}

run_logged_command() (
  local log=$1
  shift
  set -o pipefail
  "$@" 2>&1 | tee -a "$log"
)

build_experimental() (
  local status=0
  cd "$1" || return
  : > build.log || return
  run_logged_command build.log make download -j8 || status=$?
  printf 'download exit status: %s\n' "$status" | tee -a build.log
  [ "$status" -eq 0 ] || return "$status"
  run_logged_command build.log make -j"$(nproc)" || status=$?
  printf 'parallel exit status: %s\n' "$status" | tee -a build.log
  [ "$status" -ne 0 ] || return 0
  status=0
  run_logged_command build.log timeout --foreground 45m make -j1 V=s || status=$?
  printf 'serial exit status: %s\n' "$status" | tee -a build.log
  return "$status"
)

experimental_main() {
  local command=${1:?usage: experimental-build.sh clone|prepare|build|package PROFILE SOURCE [DEST]} profile=$2 tree=$3
  load_experimental_profile "$profile"
  case "$command" in
    clone)
      [ ! -e "$tree" ] || { echo 'Source checkout already exists' >&2; return 1; }
      git init "$tree"
      git -C "$tree" remote add origin "$SOURCE_REPO"
      git -C "$tree" fetch --depth=1 origin "$OPENWRT_COMMIT"
      git -C "$tree" checkout --detach FETCH_HEAD
      ;;
    prepare)
      [ "$(git -C "$tree" rev-parse HEAD)" = "$OPENWRT_COMMIT" ]
      bash "$EXPERIMENTAL_ROOT/$PROFILE_ADAPTER" "$tree"
      pin_native_feeds "$tree"
      (cd "$tree"; ./scripts/feeds update -a)
      while read -r type name location; do
        [ "$(git -C "$tree/feeds/$name" rev-parse HEAD)" = "${location##*^}" ]
      done < "$tree/feeds.conf"
      (cd "$tree"; ./scripts/feeds install -a)
      stage_profile_files "$tree"
      apply_software_policy "$tree"
      cp "$EXPERIMENTAL_ROOT/$PROFILE_CONFIG" "$tree/.config"
      if [ -n "${CCACHE_DIR:-}" ]; then
        printf '\nCONFIG_CCACHE_DIR="%s"\n' "$CCACHE_DIR" >> "$tree/.config"
      fi
      (cd "$tree"; make defconfig 2>&1 | tee defconfig.log)
      verify_resolved_config "$tree"
      write_build_provenance "$tree"
      ;;
    build)
      verify_resolved_config "$tree"
      build_experimental "$tree"
      ;;
    package)
      source "$EXPERIMENTAL_ROOT/scripts/experimental-package.sh"
      source "$EXPERIMENTAL_ROOT/scripts/validate-experimental-output.sh"
      validate_experimental_dtbs "$tree" "$ACCELERATION_POLICY" | tee "$tree/.builder-dtb-validation.txt"
      local manifest
      for manifest in "$tree"/bin/targets/qualcommax/ipq60xx/*.manifest; do
        validate_experimental_manifest "$manifest" "$ACCELERATION_POLICY" "$SOFTWARE_POLICY"
      done
      package_experimental "$tree" "${4:?artifact destination required}" "$PROFILE_ID" "$(cat "$tree/.builder-kernel")" "${GITHUB_RUN_NUMBER:-local}.${GITHUB_RUN_ATTEMPT:-1}"
      ;;
    *) echo 'Unknown build command' >&2; return 1;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then experimental_main "$@"; fi
