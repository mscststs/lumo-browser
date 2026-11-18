#!/usr/bin/env bash
# Author a patch against the Chromium checkout without a git baseline.
#
# The official tarball checkout is a git repo *without commits*, so `git diff`
# and `git checkout -- <file>` do not work there. This helper snapshots the files
# you are about to touch, exports a `git apply`-compatible patch from the
# difference, and can restore the pristine state afterwards.
#
#   scripts/chromium/patchwork.sh start <out.patch> <path...>   # snapshot (files or dirs)
#   scripts/chromium/patchwork.sh status                        # what changed so far
#   scripts/chromium/patchwork.sh export [out.patch]            # write the patch file
#   scripts/chromium/patchwork.sh revert                        # restore snapshot
#   scripts/chromium/patchwork.sh finish                        # drop snapshot (keep edits)
#
# Example:
#   scripts/chromium/patchwork.sh start patches/0012-toolbar-inline.patch \
#       chrome/browser/ui/android/toolbar/java/src/org/chromium/chrome/browser/toolbar
#   # ...edit files under ~/chromium/src...
#   scripts/chromium/patchwork.sh export
#   scripts/chromium/patchwork.sh revert        # back to pristine, edits preserved in the patch
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

STATE="$CHROMIUM_SRC/.lumo-patchwork"
PATHS_FILE="$STATE/paths"
TARGET_FILE="$STATE/target"
SNAP="$STATE/files"

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

repo_rel() { # repo_rel <path>: normalize to a src-relative path
  local p="$1"
  p="${p#./}"
  p="${p#"$CHROMIUM_SRC"/}"
  printf '%s' "${p%/}"
}

require_state() { [[ -d "$STATE" ]] || die "no active patchwork session (run: scripts/chromium/patchwork.sh start <out.patch> <path...>)"; }

# All files covered by the session: union of the snapshot and the live tree, so
# newly created files are exported too (as additions).
session_files() {
  local rel
  while IFS= read -r rel; do
    if [[ -d "$CHROMIUM_SRC/$rel" ]]; then
      ( cd "$CHROMIUM_SRC" && find "$rel" -type f )
    elif [[ -e "$CHROMIUM_SRC/$rel" ]]; then
      printf '%s\n' "$rel"
    fi
  done < "$PATHS_FILE" | sort -u
  ( cd "$SNAP" && find . -type f | sed 's|^\./||' )
}

session_files_all() { session_files | sort -u; }

cmd_start() {
  local target="${1:-}"; shift || true
  [[ -n "$target" && $# -gt 0 ]] || usage 2
  [[ -e "$STATE" ]] && die "session already active (finish or revert first)"

  mkdir -p "$SNAP"
  : > "$PATHS_FILE"
  local rel
  for p in "$@"; do
    rel="$(repo_rel "$p")"
    [[ -e "$CHROMIUM_SRC/$rel" ]] || die "not found in $CHROMIUM_SRC: $rel"
    printf '%s\n' "$rel" >> "$PATHS_FILE"
    mkdir -p "$SNAP/$(dirname "$rel")"
    cp -a "$CHROMIUM_SRC/$rel" "$SNAP/$rel"
  done
  case "$target" in
    /*) printf '%s\n' "$target" > "$TARGET_FILE" ;;
    *)  printf '%s\n' "$REPO_ROOT/$target" > "$TARGET_FILE" ;;
  esac
  log "snapshot: $(wc -l < "$PATHS_FILE") path(s) -> $SNAP"
  log "target  : $(cat "$TARGET_FILE")"
  log "edit the files, then: scripts/chromium/patchwork.sh export"
}

cmd_status() {
  require_state
  local rel changed=0
  printf 'target : %s\n' "$(cat "$TARGET_FILE")"
  while IFS= read -r rel; do
    if ! diff -rq "$SNAP/$rel" "$CHROMIUM_SRC/$rel" >/dev/null 2>&1; then
      printf '  M %s\n' "$rel"
      changed=1
    fi
  done < <(session_files_all)
  (( changed )) || printf '  (no changes yet)\n'
}

cmd_export() {
  require_state
  local target="${1:-$(cat "$TARGET_FILE")}"
  target="${target#"$REPO_ROOT"/}"
  [[ "$target" == /* ]] || target="$REPO_ROOT/$target"

  local tmp; tmp="$(mktemp)"
  local rel old new
  while IFS= read -r rel; do
    old="$SNAP/$rel"
    new="$CHROMIUM_SRC/$rel"
    if [[ -f "$new" ]] && [[ ! -e "$old" ]]; then
      old="/dev/null"
    elif [[ -e "$old" ]] && [[ ! -e "$new" ]]; then
      new="/dev/null"
    fi
    if [[ "$old" != /dev/null && "$new" != /dev/null ]] && diff -q "$old" "$new" >/dev/null 2>&1; then
      continue
    fi
    # git apply needs `--- /dev/null` for creations and `+++ /dev/null` for deletions;
    # only label the sides that actually exist.
    local olabel nlabel
    [[ "$old" == /dev/null ]] && olabel="/dev/null" || olabel="a/$rel"
    [[ "$new" == /dev/null ]] && nlabel="/dev/null" || nlabel="b/$rel"
    diff -u --label "$olabel" --label "$nlabel" "$old" "$new" >> "$tmp" || true
  done < <(session_files_all)

  if [[ ! -s "$tmp" ]]; then
    rm -f "$tmp"
    die "no changes since the snapshot"
  fi
  mkdir -p "$(dirname "$target")"
  mv "$tmp" "$target"
  log "patch: $target ($(wc -l < "$target") lines, $(grep -c '^--- ' "$target" || true) file(s))"
  log "verify: (cd $CHROMIUM_SRC && git apply --check '$target')"
}

cmd_revert() {
  require_state
  local rel
  while IFS= read -r rel; do
    if [[ -e "$SNAP/$rel" ]]; then
      rm -rf "${CHROMIUM_SRC:?}/$rel"
      mkdir -p "$(dirname "$CHROMIUM_SRC/$rel")"
      cp -a "$SNAP/$rel" "$CHROMIUM_SRC/$rel"
    else
      rm -f "$CHROMIUM_SRC/$rel"   # file did not exist before the session
    fi
  done < <(session_files_all)
  log "reverted to pristine working tree (session still active; 'finish' to drop it)"
}

cmd_finish() {
  require_state
  rm -rf "$STATE"
  log "session closed"
}

case "${1:-}" in
  start)  shift; cmd_start "$@" ;;
  status) cmd_status ;;
  export) shift || true; cmd_export "$@" ;;
  revert) cmd_revert ;;
  finish) cmd_finish ;;
  -h|--help|help) usage ;;
  *) usage 2 ;;
esac
