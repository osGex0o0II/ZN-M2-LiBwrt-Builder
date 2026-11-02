#!/bin/sh
set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
resolver="$repo_root/scripts/resolve-latest-upstreams.sh"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT HUP INT TERM

# A local bare repository stands in for the upstream: resolving it proves the
# script reports the branch tip and not the stale pin that sits next to it.
upstream="$workdir/upstream.git"
seed="$workdir/seed"
git init -q --bare "$upstream"
git init -q "$seed"
git -C "$seed" config user.email test@example.com
git -C "$seed" config user.name test
printf 'one\n' > "$seed/file"
git -C "$seed" add file
git -C "$seed" commit -qm one
git -C "$seed" branch -M trunk
git -C "$seed" remote add origin "$upstream"
git -C "$seed" push -q origin trunk
tip="$(git -C "$seed" rev-parse trunk)"
stale=0000000000000000000000000000000000000000

deps="$workdir/deps.env"
cat > "$deps" <<EOF
OPENWRT_TRACK=${upstream}#refs/heads/trunk
OPENWRT_COMMIT=${stale}
EOF

stdout_file="$workdir/stdout"
stderr_file="$workdir/stderr"
if ! sh "$resolver" "$deps" > "$stdout_file" 2> "$stderr_file"; then
	echo 'resolver failed against a reachable repository' >&2
	cat "$stderr_file" >&2
	exit 1
fi

[ "$(cat "$stdout_file")" = "OPENWRT_COMMIT=${tip}" ] || {
	echo "resolver did not report the branch tip" >&2
	sed 's/^/  got: /' "$stdout_file" >&2
	exit 1
}

# Only assignments may reach stdout: the workflow sources this stream, so a
# stray notice would abort the shell with a command-not-found error.
if grep -qv '^[A-Z][A-Z0-9_]*=[0-9a-f]\{40\}$' "$stdout_file"; then
	echo 'resolver wrote non-assignment content to stdout' >&2
	cat "$stdout_file" >&2
	exit 1
fi

grep -q 'trunk' "$stderr_file" || {
	echo 'resolver did not report which ref it tracked' >&2
	cat "$stderr_file" >&2
	exit 1
}

# An unreachable remote must degrade to the pin with a warning, never to an
# empty revision that would make the build clone nothing.
fallback="$workdir/fallback.env"
cat > "$fallback" <<EOF
OPENWRT_TRACK=${workdir}/missing.git#refs/heads/trunk
OPENWRT_COMMIT=${stale}
EOF
if ! sh "$resolver" "$fallback" > "$stdout_file" 2> "$stderr_file"; then
	echo 'resolver aborted instead of falling back to the pin' >&2
	cat "$stderr_file" >&2
	exit 1
fi
[ "$(cat "$stdout_file")" = "OPENWRT_COMMIT=${stale}" ] || {
	echo 'resolver did not fall back to the pinned revision' >&2
	cat "$stdout_file" >&2
	exit 1
}
grep -q '::warning::' "$stderr_file" || {
	echo 'resolver did not warn about the fallback' >&2
	cat "$stderr_file" >&2
	exit 1
}

# A tracked ref without any pin is a hard error: silently continuing would
# check out whatever happens to be in the tree.
orphan="$workdir/orphan.env"
cat > "$orphan" <<EOF
OPENWRT_TRACK=${workdir}/missing.git#refs/heads/trunk
EOF
if sh "$resolver" "$orphan" > /dev/null 2>&1; then
	echo 'resolver accepted a tracked ref without a fallback pin' >&2
	exit 1
fi

# Both production builds must consume the resolver; otherwise the tracking
# declarations would be inert documentation.
for workflow in zn-m2-256m-main-router.yml zn-m2-256m-6.18.yml; do
	grep -q 'scripts/resolve-latest-upstreams.sh' "$repo_root/.github/workflows/$workflow" || {
		echo "$workflow does not resolve tracked upstream refs" >&2
		exit 1
	}
done

grep -q 'OPENWRT_TRACK=' "$repo_root/deps/libwrt-6.12.env" || {
	echo 'libwrt-6.12.env does not track the upstream branch' >&2
	exit 1
}
grep -q 'OPENWRT_TRACK=' "$repo_root/deps/immortalwrt-6.18.env" || {
	echo 'immortalwrt-6.18.env does not track the upstream branch' >&2
	exit 1
}

echo 'latest upstream resolution test passed'
