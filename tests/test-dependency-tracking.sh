#!/usr/bin/env bash
#
# Contract tests for the dependency-tracking mechanism.
#
# The repository resolves upstream branch tips at build time instead of relying
# on a scheduled job to bump pins. Two things can silently break that:
#
#   * a deps file that declares a *_TRACK ref without a *_COMMIT fallback, so a
#     network hiccup resolves to an empty revision;
#   * a build path that never runs the resolver, leaving the tracking
#     declarations as inert documentation.
#
# Both are asserted here, together with the exact refs each line follows.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }

ENV_LIBWRT="$root/deps/libwrt-6.12.env"
ENV_618="$root/deps/immortalwrt-6.18.env"
ENV_VIKING="$root/deps/immortalwrt-viking-main-nss.env"
ENV_LEDE="$root/deps/lede-master-nss.env"
ENV_FANCH="$root/deps/fanchmwrt-25.12.env"
RESOLVER="$root/scripts/resolve-latest-upstreams.sh"
EXP="$root/scripts/experimental-build.sh"
WF_PROFILE="$root/.github/workflows/build-profile.yml"
WF_256="$root/.github/workflows/zn-m2-256m-main-router.yml"
WF_618="$root/.github/workflows/zn-m2-256m-6.18.yml"

for f in "$ENV_LIBWRT" "$ENV_618" "$ENV_VIKING" "$ENV_LEDE" "$ENV_FANCH" \
	"$RESOLVER" "$EXP" "$WF_PROFILE"; do
	[ -f "$f" ] || fail "missing $f"
done

# --- every tracked ref needs a fallback pin --------------------------------
check_fallbacks() {
	local file=$1 key
	for key in $(sed -n 's/^\([A-Z0-9_]*\)_TRACK=.*/\1/p' "$file"); do
		grep -q "^${key}_COMMIT=[0-9a-f]\{40\}$" "$file" ||
			fail "$(basename "$file"): ${key}_TRACK has no matching ${key}_COMMIT fallback"
	done
}
for f in "$ENV_LIBWRT" "$ENV_618" "$ENV_VIKING" "$ENV_LEDE"; do
	check_fallbacks "$f"
done

# --- the refs each line follows -------------------------------------------
expect_track() {
	local file=$1 snippet=$2
	grep -Fq "$snippet" "$file" ||
		fail "$(basename "$file") does not track: $snippet"
}

expect_track "$ENV_LIBWRT" 'OPENWRT_TRACK=https://github.com/LiBwrt/LibWrt.git#refs/heads/25.12-nss'
expect_track "$ENV_LIBWRT" 'FEED_NSS_PACKAGES_TRACK=https://github.com/qosmio/nss-packages.git#refs/heads/NSS-12.5-K6.x'
expect_track "$ENV_LIBWRT" 'FEED_PACKAGES_TRACK=https://github.com/immortalwrt/packages.git#refs/heads/openwrt-25.12'
expect_track "$ENV_LIBWRT" 'VIKINGYFY_TRACK=https://github.com/VIKINGYFY/packages.git#refs/heads/main'

expect_track "$ENV_618" 'OPENWRT_TRACK=https://github.com/VIKINGYFY/immortalwrt.git#refs/heads/owrt'
expect_track "$ENV_618" 'FEED_PACKAGES_TRACK=https://github.com/immortalwrt/packages.git#refs/heads/master'
expect_track "$ENV_618" 'VIKINGYFY_TRACK=https://github.com/VIKINGYFY/packages.git#refs/heads/main'

expect_track "$ENV_VIKING" 'OPENWRT_TRACK=https://github.com/VIKINGYFY/immortalwrt.git#refs/heads/main'
expect_track "$ENV_VIKING" 'VIKINGYFY_TRACK=https://github.com/VIKINGYFY/packages.git#refs/heads/main'

expect_track "$ENV_LEDE" 'OPENWRT_TRACK=https://github.com/coolsnowwolf/lede.git#refs/heads/master'
expect_track "$ENV_LEDE" 'FEED_LUCI_TRACK=https://github.com/coolsnowwolf/luci.git#refs/heads/openwrt-25.12'
# helloworld's default branch is `dev`; tracking `master` would freeze the feed
# on a snapshot that lags the active line by hundreds of commits.
expect_track "$ENV_LEDE" 'FEED_HELLOWORLD_TRACK=https://github.com/fw876/helloworld.git#refs/heads/dev'

# coolsnwolf/routing only publishes `main` and has not moved since 2026-09-11,
# so it stays a fixed pin rather than a tracked ref.
if grep -q 'FEED_ROUTING_TRACK=' "$ENV_LEDE"; then
	fail 'lede-master-nss.env must not track coolsnwolf/routing: it has no moving branch'
fi

# --- FanchmWrt is intentionally not tracked -------------------------------
if grep -q '_TRACK=' "$ENV_FANCH"; then
	fail 'fanchmwrt-25.12.env must stay on fixed pins: the fork branch is static'
fi
grep -q '^OPENWRT_COMMIT=[0-9a-f]\{40\}$' "$ENV_FANCH" ||
	fail 'fanchmwrt-25.12.env lost its fixed source pin'
# The fanchmwrt feed lives in its own repository, not in the firmware fork.
grep -q 'fanchmwrt/fanchmwrt-packages' "$ENV_FANCH" ||
	fail 'fanchmwrt-25.12.env does not name the real feed repository'

# --- the resolver is wired into every build path --------------------------
grep -Fq 'OPENWRT_RESOLVED_DEPS' "$EXP" ||
	fail 'experimental-build.sh does not consume the resolved refs'
grep -Fq 'resolve-latest-upstreams.sh' "$WF_PROFILE" ||
	fail 'build-profile.yml never resolves tracked refs'
for wf in "$WF_256" "$WF_618"; do
	grep -Fq 'scripts/resolve-latest-upstreams.sh' "$wf" ||
		fail "$(basename "$wf") never resolves tracked refs"
done

# The resolver output must be sourced after the pin file, otherwise the
# offline fallback wins over the branch tip.
fallback_line=$(grep -n 'source "\$EXPERIMENTAL_ROOT/\$SOURCE_PINS"' "$EXP" | cut -d: -f1)
resolved_line=$(grep -n 'source "\$OPENWRT_RESOLVED_DEPS"' "$EXP" | cut -d: -f1)
[ -n "$fallback_line" ] && [ -n "$resolved_line" ] ||
	fail 'experimental-build.sh lost one of its two pin sources'
[ "$resolved_line" -gt "$fallback_line" ] ||
	fail 'the resolved deps are sourced before the pin file and would be overwritten'

# --- the resolver still degrades safely -----------------------------------
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM
cat > "$tmp/orphan.env" <<'EOF'
OPENWRT_TRACK=/nonexistent/repo.git#refs/heads/main
EOF
if sh "$RESOLVER" "$tmp/orphan.env" >/dev/null 2>&1; then
	fail 'the resolver accepted a tracked ref with no fallback pin'
fi
cat > "$tmp/fallback.env" <<'EOF'
OPENWRT_TRACK=/nonexistent/repo.git#refs/heads/main
OPENWRT_COMMIT=1111111111111111111111111111111111111111
EOF
out=$(sh "$RESOLVER" "$tmp/fallback.env" 2>/dev/null)
[ "$out" = 'OPENWRT_COMMIT=1111111111111111111111111111111111111111' ] ||
	fail 'the resolver did not fall back to the pinned revision'

# --- the Aurora theme stays a reviewed pin --------------------------------
for f in "$ENV_LIBWRT" "$ENV_618" "$ENV_VIKING" "$ENV_LEDE"; do
	grep -q '^AURORA_COMMIT=[0-9a-f]\{40\}$' "$f" ||
		fail "$(basename "$f") lost the Aurora pin"
	if grep -q '^AURORA_TRACK=' "$f"; then
		fail "$(basename "$f") must not auto-track the theme: it ships untagged commits"
	fi
done

echo 'PASS: dependency tracking refs, fallbacks and build wiring'
