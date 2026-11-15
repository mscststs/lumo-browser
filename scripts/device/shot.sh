#!/usr/bin/env bash
# Take a screenshot into artifacts/shots/ (and print the path).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
need_device
OUT="${1:-$REPO_ROOT/artifacts/shots/$(date +%Y%m%d-%H%M%S).png}"
shot "$OUT"
