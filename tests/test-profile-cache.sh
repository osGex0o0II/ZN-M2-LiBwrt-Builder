#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
sed -n "/^          awk -F/,/^          ' caches.tsv/p" .github/workflows/prune-caches.yml | sed '1d;$d' > "$tmp/select.awk"
for profile in immortalwrt-viking-owrt-ppe immortalwrt-viking-main-nss libwrt-25.12-nss; do
  for n in 1 2 3; do
    printf '%s\trefs/heads/main\tLinux-openwrt-dl-profile_%s__-%s\t100\n' "$profile-$n" "$profile" "$n"
  done
done > "$tmp/caches.tsv"
awk -F '\t' -f "$tmp/select.awk" "$tmp/caches.tsv" > "$tmp/stale.tsv"
[ "$(wc -l < "$tmp/stale.tsv")" = 3 ]
for profile in immortalwrt-viking-owrt-ppe immortalwrt-viking-main-nss libwrt-25.12-nss; do
 grep -q "^$profile-3" "$tmp/stale.tsv"
done
echo 'PASS: retention independently preserves two generations of each full profile identity'
