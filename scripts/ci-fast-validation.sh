#!/usr/bin/env bash
# Fast PR checks. No OpenWrt checkout, feeds or cross-compile toolchain.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
  git fetch --no-tags --depth=1 origin "$GITHUB_BASE_REF"
  git diff --check FETCH_HEAD HEAD
else
  git diff --check
fi

# Validate the entire Actions graph, including reusable workflow inputs and
# GitHub expression syntax. Pin the binary and verify its published SHA-256.
actionlint_dir="$(mktemp -d)"
trap 'rm -rf "$actionlint_dir"' EXIT
curl --fail --silent --show-error --location --retry 3 \
  --output "$actionlint_dir/actionlint.tar.gz" \
  "https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_amd64.tar.gz"
printf '%s  %s\n' \
  '8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8' \
  "$actionlint_dir/actionlint.tar.gz" | sha256sum --check --status
tar -xzf "$actionlint_dir/actionlint.tar.gz" -C "$actionlint_dir" actionlint
# Actionlint v1.7.12 predates GitHub-hosted ubuntu-26.04, which is already
# running our real workflow jobs. Suppress only that one outdated-label warning.
"$actionlint_dir/actionlint" -shellcheck= \
  -ignore 'label "ubuntu-26\.04" is unknown'

python3 -m unittest discover -s tests -p 'test_ci_change_scope.py' -v

# Static shell syntax for every source and test, including scripts not exercised
# in the lightweight fixtures. The cross-compile scripts are never executed.
while IFS= read -r -d '' file; do
  bash -n "$file"
done < <(find scripts tests -type f -name '*.sh' -print0)
for file in adapters/*.sh; do
  bash -n "$file"
done

# Repository-only fixtures. The few tests that need an upstream source tree,
# kernel source or a network-connected feed remain inside full build jobs.
for test in \
  tests/test-ci-gate.sh \
  tests/test-workflow-contracts.sh \
  tests/test-build-catalog.sh \
  tests/test-immortalwrt-6.18-contracts.sh \
  tests/test-release-retention.sh \
  tests/test-release-notes.sh \
  tests/test-profile-policy.sh \
  tests/test-honk-profile.sh \
  tests/test-dependency-tracking.sh \
  tests/test-latest-upstreams.sh \
  tests/test-package-source-contracts.sh \
  tests/test-profile-cache.sh \
  tests/test-profile-manifest.sh \
  tests/test-profile-logging.sh \
  tests/test-profile-package.sh \
  tests/test-profile-prepare.sh \
  tests/test-uci-defaults.sh \
  tests/test-wired-hardware.sh \
  tests/test-dropbear-hardening.sh \
  tests/test-upgrade-migrations.sh \
  tests/test-healthcheck-hardening.sh \
  tests/test-dhcp-primer.sh \
  tests/test-dhcp-primer-ipcalc.sh \
  tests/test-ecm-module-deps.sh \
  tests/test-cpubench-hardening.sh \
  tests/test-luci-port-order.sh \
  tests/test-foreign-config-cleanup.sh \
  tests/test-led-sysfs-normalize.sh \
  tests/test-runtime-defaults.sh; do
  echo "::group::$test"
  bash "$test"
  echo "::endgroup::"
done

echo 'All fast CI checks passed'
