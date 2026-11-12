#!/bin/sh
# Resolve the tracked upstream refs declared in a deps/*.env file.
#
# Every "<KEY>_TRACK=<repo-url>#<ref>" line makes this script resolve <KEY>_COMMIT
# to the current tip of <ref>, so a build always uses the latest upstream state
# of the stable branch instead of a hand-bumped pin. When the remote cannot be
# reached the previous pinned <KEY>_COMMIT from the same file is emitted instead:
# a network hiccup must never silently produce a stale tree, but it must not
# fail the build either, so the fallback is reported as a warning.
#
# Only KEY=VALUE assignments go to stdout (they are appended to $GITHUB_ENV or
# sourced), every notice goes to stderr.
set -eu

deps_file=${1:?usage: resolve-latest-upstreams.sh DEPS_FILE}

if [ ! -f "$deps_file" ]; then
	echo "Missing deps file: ${deps_file}" >&2
	exit 1
fi

tracked=$(sed -n 's/^\([A-Z0-9_]*\)_TRACK=.*/\1/p' "$deps_file")
if [ -z "$tracked" ]; then
	echo "No *_TRACK entries in ${deps_file}" >&2
	exit 1
fi

# shellcheck disable=SC1090
. "$deps_file"

resolved_count=0
fallback_count=0

for key in $tracked; do
	eval "spec=\${${key}_TRACK}"
	repo=${spec%%#*}
	ref=${spec#*#}
	if [ "$repo" = "$spec" ] || [ -z "$ref" ]; then
		echo "Malformed ${key}_TRACK (expected <url>#<ref>): ${spec}" >&2
		exit 1
	fi
	# Read the fallback from the file, not from the shell. The workflows export
	# OPENWRT_COMMIT and the feed pins into the job environment, so an eval of
	# the variable would silently pick up a stale value from an earlier step
	# instead of the pin this file declares.
	pinned=$(sed -n "s/^${key}_COMMIT=//p" "$deps_file" | head -n 1)

	if sha=$(git ls-remote "$repo" "$ref" 2>/dev/null | awk 'NR==1 {print $1}') &&
		[ -n "$sha" ]; then
		printf '%s_COMMIT=%s\n' "$key" "$sha"
		echo "${key} tracks ${repo} ${ref} -> ${sha}" >&2
		resolved_count=$((resolved_count + 1))
	elif [ -n "$pinned" ]; then
		printf '%s_COMMIT=%s\n' "$key" "$pinned"
		echo "::warning::${key}: cannot resolve ${repo} ${ref}; falling back to pinned ${pinned}" >&2
		fallback_count=$((fallback_count + 1))
	else
		echo "::error::${key}: cannot resolve ${repo} ${ref} and no pinned fallback exists" >&2
		exit 1
	fi
done

echo "Resolved ${resolved_count} upstream ref(s), ${fallback_count} fallback(s)" >&2
