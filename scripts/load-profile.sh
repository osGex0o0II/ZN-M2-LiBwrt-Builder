#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
id=${1:?usage: load-profile.sh PROFILE_ID}
case "$id" in .*|''|*[!a-z0-9.-]*) echo "Invalid profile ID" >&2; exit 1;; esac
[ -f "$root/profiles/$id.conf" ] || { echo "Unknown profile: $id" >&2; exit 1; }
source "$root/profiles/$id.conf"
[ "$PROFILE_ID" = "$id" ]
case "$ACCELERATION_POLICY" in nss|ppe|upstream-native) ;; *) exit 1;; esac
case "$SOFTWARE_POLICY" in aurora-homeproxy|upstream-native) ;; *) exit 1;; esac
for path in "$SOURCE_PINS" "$PROFILE_CONFIG" "$PROFILE_ADAPTER"; do
  [ -f "$root/$path" ] || { echo "Missing profile input: $path" >&2; exit 1; }
done
for key in PROFILE_ID SOURCE_REPO SOURCE_BRANCH SOURCE_PINS PROFILE_CONFIG ACCELERATION_POLICY SOFTWARE_POLICY PROFILE_ADAPTER; do
  printf '%s=%s\n' "$key" "${!key}"
done
printf 'CACHE_NAMESPACE=%s\n' "$PROFILE_ID"
