#!/bin/sh
# Every build line has exactly one display name, it is unique, and the user
# guide plus the dedicated workflow use the same string.
set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
profiles="$repo_root/profiles"
readme="$repo_root/README.md"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

titles=""
count=0
for conf in "$profiles"/*.conf; do
	id="$(sed -n 's/^PROFILE_ID=//p' "$conf")"
	title="$(sed -n 's/^PROFILE_TITLE=//p' "$conf" | tr -d '"')"

	[ -n "$id" ] || fail "$(basename "$conf") has no PROFILE_ID"
	[ -n "$title" ] || fail "$(basename "$conf") has no PROFILE_TITLE"

	case "
$titles
" in
	*"
$title
"*) fail "duplicate PROFILE_TITLE: $title" ;;
	esac
	titles="$titles$title
"

	grep -Fq "$title" "$readme" || fail "README does not document $title"
	count=$((count + 1))
done

[ "$count" -ge 5 ] || fail "expected at least five build lines, found $count"

# The three promoted lines must expose the same title in their workflow.
for pair in \
	"zn-m2-256m-viking-nss.yml|ZN-M2 VIKING 6.18 NSS" \
	"zn-m2-256m-lede-nss.yml|ZN-M2 LEDE 6.12 NSS" \
	"zn-m2-256m-fanchmwrt-fwx.yml|ZN-M2 FanchmWrt 6.12 FWX"; do
	file="${pair%%|*}"
	title="${pair#*|}"
	wf="$repo_root/.github/workflows/$file"
	[ -f "$wf" ] || fail "missing $file"
	grep -Fq "name: $title" "$wf" || fail "$file name does not match $title"
done

echo "build catalog test passed ($count build lines)"
