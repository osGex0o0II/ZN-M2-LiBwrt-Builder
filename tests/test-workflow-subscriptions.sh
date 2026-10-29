#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
subscriptions=$(awk '
  /^  workflow_run:/ { section=1; next }
  section && /^  [^ ]/ { section=0 }
  section && /^    workflows:/ { list=1; next }
  list && /^    [a-z]/ { list=0 }
  list && /^      - / { sub(/^      - /, ""); print }
' "$root/.github/workflows/auto-merge-deps.yml")
for workflow in zn-m2-256m-main-router.yml zn-m2-256m-6.18.yml; do
  name=$(sed -n 's/^name: //p' "$root/.github/workflows/$workflow")
  printf '%s\n' "$subscriptions" | grep -Fxq "$name" || {
    echo "FAIL: dependency auto-merge will not receive completed event: $name" >&2; exit 1;
  }
done
echo 'PASS: dependency auto-merge subscribes to both actual mature workflow names'
