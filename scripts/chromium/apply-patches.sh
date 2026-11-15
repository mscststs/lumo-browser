#!/usr/bin/env bash
# Apply patches/NNNN-*.patch onto a clean Chromium checkout, in order.
# Idempotent: skips patches already applied; fails with the offending patch.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

SRC="${1:-$CHROMIUM_SRC}"
PATCH_DIR="$REPO_ROOT/patches"
[[ -d "$SRC" ]] || die "missing source: $SRC"

shopt -s nullglob
patches=( "$PATCH_DIR"/[0-9][0-9][0-9][0-9]-*.patch )
shopt -u nullglob

if (( ${#patches[@]} == 0 )); then
  log "no patches yet"
  exit 0
fi

for p in "${patches[@]}"; do
  name="$(basename "$p")"
  if ( cd "$SRC" && git apply --reverse --check "$p" >/dev/null 2>&1 ); then
    log "skip (already applied): $name"
    continue
  fi
  log "apply: $name"
  ( cd "$SRC" && git apply --index --whitespace=nowarn "$p" ) \
    || die "failed to apply $name (rebase needed: git -C $SRC am -3 $p)"
done
log "patches applied"
