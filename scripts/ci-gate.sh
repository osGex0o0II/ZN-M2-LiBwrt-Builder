#!/usr/bin/env bash
# Strict required-check gate for a PR; never treats an unexpected skip as success.
set -euo pipefail

require_job() {
  local required="$1" result="$2" label="$3"
  case "$required" in
    true)
      if [[ "$result" != success ]]; then
        echo "::error::$label must complete successfully (got: $result)" >&2
        exit 1
      fi
      ;;
    false)
      if [[ "$result" != skipped ]]; then
        echo "::error::$label must be skipped for a non-impacting PR (got: $result)" >&2
        exit 1
      fi
      ;;
    *)
      echo "::error::Invalid or missing impact classification for $label" >&2
      exit 1
      ;;
  esac
}

if [[ "${CHANGES_RESULT:-}" != success || "${QUICK_RESULT:-}" != success ]]; then
  echo "::error::Change classification or fast tests failed" >&2
  exit 1
fi

require_job "${PROFILE_REQUIRED:-}" "${PROFILE_RESULT:-}" "primary firmware"

if [[ -n "${VIKING_REQUIRED:-}" || -n "${FANCH_REQUIRED:-}" ||
      -n "${VIKING_RESULT:-}" || -n "${FANCH_RESULT:-}" ]]; then
  require_job "${VIKING_REQUIRED:-}" "${VIKING_RESULT:-}" "Viking NSS"
  require_job "${FANCH_REQUIRED:-}" "${FANCH_RESULT:-}" "FanchmWrt FWX"
fi

echo "PR gate passed: all required checks and affected builds succeeded"
