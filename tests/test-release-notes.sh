#!/usr/bin/env bash
# The release notes are the only place the checksums are published, so the
# generator must always name both images, embed their SHA256, and stay Chinese.
set -euo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
script="$repo_root/scripts/release-notes.sh"

fail() { echo "test-release-notes: $*" >&2; exit 1; }

[ -f "$script" ] || fail "missing $script"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT HUP INT TERM

assets="$workdir/assets"
mkdir -p "$assets"
factory="$assets/ZN-M2-256M-libwrt-25.12-nss-6.12-1-factory.ubi"
sysupgrade="$assets/ZN-M2-256M-libwrt-25.12-nss-6.12-1-sysupgrade.bin"
printf 'factory-image' > "$factory"
printf 'sysupgrade-image' > "$sysupgrade"

factory_sha="$(sha256sum "$factory" | awk '{print $1}')"
sysupgrade_sha="$(sha256sum "$sysupgrade" | awk '{print $1}')"

for profile in \
	libwrt-25.12-nss \
	immortalwrt-viking-owrt-ppe \
	immortalwrt-viking-main-nss \
	lede-master-nss \
	fanchmwrt-25.12; do
	notes="$workdir/$profile.md"
	bash "$script" "$profile" "$assets" > "$notes"

	grep -Fq '### 默认设置' "$notes" || fail "$profile: missing default settings section"
	grep -Fq '192.168.1.1' "$notes" || fail "$profile: missing management address"
	grep -Fq 'root' "$notes" || fail "$profile: missing user name"
	grep -Fq '### 文件校验（SHA256）' "$notes" || fail "$profile: missing checksum section"
	grep -Fq "$factory_sha" "$notes" || fail "$profile: factory checksum missing"
	grep -Fq "$sysupgrade_sha" "$notes" || fail "$profile: sysupgrade checksum missing"
	grep -Fq "$(basename "$factory")" "$notes" || fail "$profile: factory file name missing"
	grep -Fq "$(basename "$sysupgrade")" "$notes" || fail "$profile: sysupgrade file name missing"

	# The trimmed release must not advertise artifacts that are no longer attached.
	if grep -Fq 'BUILD-MANIFEST.txt' "$notes"; then
		fail "$profile: notes still reference the manifest attachment"
	fi
	if grep -Fq 'profiles.json' "$notes"; then
		fail "$profile: notes still reference profiles.json"
	fi
	if grep -Fq 'SHA256SUMS' "$notes"; then
		fail "$profile: notes still reference a SHA256SUMS attachment"
	fi
done

grep -Fq 'password' "$workdir/lede-master-nss.md" ||
	fail "LEDE notes must state the public default password"
grep -Fq 'FWX' "$workdir/fanchmwrt-25.12.md" ||
	fail "FanchmWrt notes must state the FWX acceleration"
grep -Fq 'HomeProxy' "$workdir/lede-master-nss.md" ||
	fail "LEDE notes must still list the HomeProxy plugin"
grep -Fq 'doona' "$workdir/libwrt-25.12-nss.md" ||
	fail "LiBwrt notes must list the doona dashboard"

if bash "$script" unknown-profile "$assets" >/dev/null 2>&1; then
	fail "unknown profile must be rejected"
fi
if bash "$script" libwrt-25.12-nss "$workdir/missing" >/dev/null 2>&1; then
	fail "missing assets directory must be rejected"
fi

single="$workdir/single"
mkdir -p "$single"
cp "$factory" "$single/"
if bash "$script" libwrt-25.12-nss "$single" >/dev/null 2>&1; then
	fail "a release without the sysupgrade image must be rejected"
fi

echo "release notes regression test passed"
