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

# Release titles are the plain build name; the version lives in the tag only.
for wf in \
	"$repo_root/.github/workflows/zn-m2-256m-6.18.yml" \
	"$repo_root/.github/workflows/zn-m2-256m-main-router.yml"; do
	if grep -Eq 'name: ZN-M2 .* - v\$' "$wf"; then
		fail "$(basename "$wf") still appends the version to the release title"
	fi
done

grep -Fq -- '--title "${TITLE}"' "$repo_root/.github/workflows/publish-profile.yml" ||
	fail "variant releases still append the version to the title"

# The publish job never checks out the repository, so gh must not fall back to
# git, and the tag must not repeat the slug's own zn-m2- prefix.
grep -Fq 'GH_REPO: ${{ github.repository }}' "$repo_root/.github/workflows/publish-profile.yml" ||
	fail "publish job does not pin GH_REPO"
if grep -Fq -- '-zn-m2-${SLUG}' "$repo_root/.github/workflows/publish-profile.yml"; then
	fail "variant tag repeats the zn-m2 prefix"
fi

echo "build catalog test passed ($count build lines)"
