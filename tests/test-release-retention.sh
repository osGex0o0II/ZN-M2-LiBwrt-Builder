#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

workflow=.github/workflows/zn-m2-256m-6.18.yml

# Pull the release selector straight out of the workflow, between the opening
# quote and the closing one, so the test exercises the shipped expression.
sed -n "/^[[:space:]]*'\[\.\[\]\[\]/,/'$/p" "$workflow" |
	sed -e "s/^[[:space:]]*'//" -e "s/'[[:space:]]*$//" > "$tmp/selector.jq"

sed -n 's/^[[:space:]]*RELEASE_TAG_SUFFIX:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$workflow" |
	sed -n '1p' > "$tmp/suffix"
sed -n 's/^[[:space:]]*KEEP_RELEASES:[[:space:]]*"\([0-9][0-9]*\)".*/\1/p' "$workflow" |
	sed -n '1p' > "$tmp/keep"

[ -s "$tmp/selector.jq" ]
[ -s "$tmp/suffix" ]
[ -s "$tmp/keep" ]

jq -n '
	[
		[
			(range(1; 6) as $i
				| {
					tag_name: ("v" + ($i | tostring) + "-zn-m2-immortalwrt-6.18-ppe"),
					published_at: ("2026-10-" + (($i + 10) | tostring) + "T00:00:00Z")
				}),
			(range(1; 5) as $i
				| {
					tag_name: ("v" + ($i | tostring) + "-zn-m2-immortalwrt-6.18"),
					published_at: ("2026-09-" + (if $i < 10 then "0" else "" end) + ($i | tostring) + "T00:00:00Z")
				}),
			{tag_name: "v99-zn-m2-libwrt", published_at: "2026-09-01T00:00:00Z"},
			{tag_name: "v0-zn-m2-immortalwrt-6.18-ppe", published_at: null}
		]
	]
' > "$tmp/releases.json"

jq -r --arg suffix "$(cat "$tmp/suffix")" --argjson keep "$(cat "$tmp/keep")" -f "$tmp/selector.jq" "$tmp/releases.json" | tr -d '\r' > "$tmp/actual"
printf '%s\n' v4-zn-m2-immortalwrt-6.18-ppe v3-zn-m2-immortalwrt-6.18-ppe v2-zn-m2-immortalwrt-6.18-ppe v1-zn-m2-immortalwrt-6.18-ppe > "$tmp/expected"
if ! diff -u "$tmp/expected" "$tmp/actual"; then
	echo "FAIL: with KEEP_RELEASES=$(cat "$tmp/keep") only the releases older than the newest one may be deleted"
	exit 1
fi
echo "PASS: workflow jq keeps only the newest PPE release (KEEP_RELEASES=$(cat "$tmp/keep")); legacy, other variants and drafts are untouched"
