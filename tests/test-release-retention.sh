#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python - "$tmp" <<'PY'
import json, pathlib, re, sys
root=pathlib.Path(sys.argv[1])
s=pathlib.Path('.github/workflows/zn-m2-256m-6.18.yml').read_text()
selector=re.search(r"                  '(\[\.\[\]\[\].*?)'\n",s,re.S).group(1)
suffix=re.search(r'RELEASE_TAG_SUFFIX: (\S+)',s).group(1)
keep=re.search(r'KEEP_RELEASES: "(\d+)"',s).group(1)
(root/'selector.jq').write_text(selector)
(root/'suffix').write_text('-'+suffix)
(root/'keep').write_text(keep)
releases=[]
for i in range(1,6):
 releases.append(dict(tag_name=f'v{i}-zn-m2-immortalwrt-6.18-ppe',published_at=f'2026-10-{10+i:02d}T00:00:00Z'))
for i in range(1,5):
 releases.append(dict(tag_name=f'v{i}-zn-m2-immortalwrt-6.18',published_at=f'2026-09-{i:02d}T00:00:00Z'))
releases += [dict(tag_name='v99-zn-m2-libwrt',published_at='2026-09-01T00:00:00Z'),dict(tag_name='v0-zn-m2-immortalwrt-6.18-ppe',published_at=None)]
(root/'releases.json').write_text(json.dumps([releases]))
PY
jq -r --arg suffix "$(cat "$tmp/suffix")" --argjson keep "$(cat "$tmp/keep")" -f "$tmp/selector.jq" "$tmp/releases.json" | tr -d '\r' > "$tmp/actual"
printf '%s\n' v4-zn-m2-immortalwrt-6.18-ppe v3-zn-m2-immortalwrt-6.18-ppe v2-zn-m2-immortalwrt-6.18-ppe v1-zn-m2-immortalwrt-6.18-ppe > "$tmp/expected"
if ! diff -u "$tmp/expected" "$tmp/actual"; then
 echo "FAIL: with KEEP_RELEASES=$(cat "$tmp/keep") only the releases older than the newest one may be deleted"
 exit 1
fi
echo "PASS: workflow jq keeps only the newest PPE release (KEEP_RELEASES=$(cat "$tmp/keep")); legacy, other variants and drafts are untouched"
