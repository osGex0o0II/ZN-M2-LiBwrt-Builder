#!/usr/bin/env bash
# Fail-closed simulations for the two required status checks.
set -euo pipefail
cd "$(dirname "$0")/.."

gate=scripts/ci-gate.sh
pass() {
  env CHANGES_RESULT=success QUICK_RESULT=success "$@" bash "$gate" >/dev/null
}
reject() {
  if env CHANGES_RESULT=success QUICK_RESULT=success "$@" bash "$gate" >/dev/null 2>&1; then
    echo "FAIL: unexpected gate approval ($*)" >&2
    exit 1
  fi
}

pass PROFILE_REQUIRED=false PROFILE_RESULT=skipped
pass PROFILE_REQUIRED=true PROFILE_RESULT=success
pass PROFILE_REQUIRED=false PROFILE_RESULT=skipped \
  VIKING_REQUIRED=true VIKING_RESULT=success \
  FANCH_REQUIRED=false FANCH_RESULT=skipped

reject PROFILE_REQUIRED=true PROFILE_RESULT=skipped
reject PROFILE_REQUIRED=true PROFILE_RESULT=failure
reject PROFILE_REQUIRED=false PROFILE_RESULT=success
reject PROFILE_REQUIRED=unknown PROFILE_RESULT=skipped
reject PROFILE_RESULT=skipped
reject CHANGES_RESULT=failure PROFILE_REQUIRED=false PROFILE_RESULT=skipped
reject QUICK_RESULT=failure PROFILE_REQUIRED=false PROFILE_RESULT=skipped
reject PROFILE_REQUIRED=false PROFILE_RESULT=skipped \
  VIKING_REQUIRED=true VIKING_RESULT=failure \
  FANCH_REQUIRED=false FANCH_RESULT=skipped
reject PROFILE_REQUIRED=false PROFILE_RESULT=skipped \
  VIKING_REQUIRED=false VIKING_RESULT=skipped \
  FANCH_REQUIRED=true FANCH_RESULT=skipped
reject PROFILE_REQUIRED=false PROFILE_RESULT=skipped \
  VIKING_REQUIRED=true VIKING_RESULT=success

echo "PASS: required PR gates fail closed on missing, failed or skipped builds"
