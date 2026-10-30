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
(root/'selector.jq').write_text(selector)
(root/'suffix').write_text('-'+suffix)
releases=[]
for i in range(1,6):
 releases.append(dict(tag_name=f'v{i}-zn-m2-immortalwrt-6.18-ppe',published_at=f'2026-10-{10+i:02d}T00:00:00Z'))
for i in range(1,5):
 releases.append(dict(tag_name=f'v{i}-zn-m2-immortalwrt-6.18',published_at=f'2026-09-{i:02d}T00:00:00Z'))
releases += [dict(tag_name='v99-zn-m2-libwrt',published_at='2026-09-01T00:00:00Z'),dict(tag_name='v0-zn-m2-immortalwrt-6.18-ppe',published_at=None)]
(root/'releases.json').write_text(json.dumps([releases]))
PY
jq -r --arg suffix "$(cat "$tmp/suffix")" --argjson keep 3 -f "$tmp/selector.jq" "$tmp/releases.json" | tr -d '\r' > "$tmp/actual"
printf '%s\n' v2-zn-m2-immortalwrt-6.18-ppe v1-zn-m2-immortalwrt-6.18-ppe > "$tmp/expected"
if ! diff -u "$tmp/expected" "$tmp/actual"; then
 echo 'FAIL: deletion must contain only PPE versions older than newest three; legacy releases immutable'
 exit 1
fi
echo 'PASS: actual workflow jq deletes only two old PPE releases; all four legacy, newest three PPE, other variant and draft retained'
