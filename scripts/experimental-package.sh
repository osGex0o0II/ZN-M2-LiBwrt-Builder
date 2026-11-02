#!/usr/bin/env bash
# Package only the selected board and preserve upstream checksum provenance.
package_experimental() (
  set -euo pipefail
  local source=$1 destination=$2 profile=$3 kernel=$4 version=$5
  local images="$source/bin/targets/qualcommax/ipq60xx" file old name expected actual
  local factory upgrade prefix
  local -a factories upgrades manifests buildinfos
  for name in "$profile" "$kernel" "$version"; do
    case "$name" in ''|*[!a-zA-Z0-9.-]*) echo 'Invalid artifact identity' >&2; return 1;; esac
  done
  mapfile -t factories < <(find "$images" -maxdepth 1 -type f -name '*zn_m2*squashfs-factory.ubi' | sort)
  mapfile -t upgrades < <(find "$images" -maxdepth 1 -type f -name '*zn_m2*squashfs-sysupgrade.bin' | sort)
  mapfile -t manifests < <(find "$images" -maxdepth 1 -type f -name '*.manifest' | sort)
  mapfile -t buildinfos < <(find "$images" -maxdepth 1 -type f -name '*.buildinfo' | sort)
  if [ "${#factories[@]}" -ne 1 ] || [ "${#upgrades[@]}" -ne 1 ] || [ "${#manifests[@]}" -ne 1 ]; then
    echo 'Expected one ZN-M2 factory, sysupgrade and package manifest' >&2; return 1
  fi
  [ -f "$source/BUILD-MANIFEST.txt" ] && [ -f "$source/.config" ] || return 1
  jq -e '(.profiles | keys) == ["zn_m2"]' "$images/profiles.json" >/dev/null || return 1
  for file in "${factories[0]}" "${upgrades[0]}"; do
    old=$(basename "$file")
    expected=$(jq -er --arg name "$old" '[.profiles.zn_m2.images[] | select(.name == $name) | .sha256] | if length == 1 then .[0] else error("image metadata missing or duplicated") end' "$images/profiles.json") || return 1
    actual=$(sha256sum "$file") || return 1
    [ "${actual%% *}" = "$expected" ] || { echo "Source image checksum mismatch: $old" >&2; return 1; }
  done
  if [ -e "$destination" ]; then
    echo 'Artifact destination already exists; refusing to mix build outputs' >&2; return 1
  fi
  mkdir -p "$destination" || return 1
  prefix="ZN-M2-256M-${profile}-${kernel}-${version}"
  factory="${prefix}-factory.ubi"
  upgrade="${prefix}-sysupgrade.bin"
  cp "${factories[0]}" "$destination/$factory" || return 1
  cp "${upgrades[0]}" "$destination/$upgrade" || return 1
  cp "${manifests[0]}" "$source/BUILD-MANIFEST.txt" "$destination/" || return 1
  cp "$source/.config" "$destination/config.buildinfo" || return 1
  for file in "${buildinfos[@]}"; do
    [ "$(basename "$file")" = config.buildinfo ] || cp "$file" "$destination/" || return 1
  done
  jq --arg old_factory "$(basename "${factories[0]}")" --arg factory "$factory" \
    --arg old_upgrade "$(basename "${upgrades[0]}")" --arg upgrade "$upgrade" \
    '.profiles.zn_m2.images |= map(if .name == $old_factory then .name = $factory elif .name == $old_upgrade then .name = $upgrade else empty end)' \
    "$images/profiles.json" > "$destination/profiles.json" || return 1
  printf '%s\n' 'EXPERIMENTAL: build success does not establish device boot, upgrade safety or acceleration.' > "$destination/VALIDATION.txt" || return 1
  (cd "$destination" && find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS && sha256sum -c SHA256SUMS) || return 1
)
