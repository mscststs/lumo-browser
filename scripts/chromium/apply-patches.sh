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

STAMPS="$SRC/.lumo-patches"
mkdir -p "$STAMPS"
for p in "${patches[@]}"; do
  name="$(basename "$p")"
  # A stamp records that this exact patch was applied to this checkout. The
  # reverse-check alone is not reliable because later patches/hand edits modify
  # the same files.
  if [[ -f "$STAMPS/$name.stamp" ]] && grep -qx "$(sha256sum "$p" | cut -d' ' -f1)" "$STAMPS/$name.stamp"; then
    log "skip (already applied): $name"
    continue
  fi
  if ( cd "$SRC" && git apply --reverse --check "$p" >/dev/null 2>&1 ); then
    log "skip (already applied, reverse-check): $name"
    sha256sum "$p" | cut -d' ' -f1 > "$STAMPS/$name.stamp"
    continue
  fi
  log "apply: $name"
  ( cd "$SRC" && git apply --whitespace=nowarn "$p" ) \
    || die "failed to apply $name (rebase needed: git -C $SRC am -3 $p)"
  sha256sum "$p" | cut -d' ' -f1 > "$STAMPS/$name.stamp"
done
log "patches applied"
