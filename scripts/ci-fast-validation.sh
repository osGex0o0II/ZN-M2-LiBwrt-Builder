#!/usr/bin/env bash
# Fast local checks. No OpenWrt checkout, feeds or cross-compile toolchain.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
  git fetch --no-tags --depth=1 origin "$GITHUB_BASE_REF"
  git diff --check FETCH_HEAD HEAD
else
  git diff --check
fi

python3 -m unittest discover -s tests -p 'test_ci_change_scope.py' -v

while IFS= read -r -d '' file; do
  bash -n "$file"
done < <(find scripts tests -type f -name '*.sh' -print0)

for file in libwrt-6.12.sh immortalwrt-6.18.sh; do
  bash -n "$file"
done

for test in \
  tests/test-workflow-contracts.sh \
  tests/test-workflow-subscriptions.sh \
  tests/test-build-catalog.sh \
  tests/test-release-retention.sh \
  tests/test-release-notes.sh \
  tests/test-profile-policy.sh \
  tests/test-ci-gate.sh; do
  bash "$test"
done

echo 'Fast PR regression checks passed'
