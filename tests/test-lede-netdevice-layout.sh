#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo"
"${PYTHON:-python3}" tests/test-lede-netdevice-layout.py "$@"
