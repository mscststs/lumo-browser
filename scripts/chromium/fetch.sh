#!/usr/bin/env bash
# Fetch Chromium source for Android. Idempotent: re-runs gclient sync.
#
#   scripts/chromium/fetch.sh            # first fetch (~30GB, hours on slow links)
#   scripts/chromium/fetch.sh --sync     # update an existing checkout
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

if [[ ! -d "$DEPOT_TOOLS" ]]; then
  step "cloning depot_tools"
  git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS"
fi

if [[ ! -f "$CHROMIUM_ROOT/.gclient" ]]; then
  step "gclient config (android, desktop-android extensions path)"
  mkdir -p "$CHROMIUM_ROOT"
  ( cd "$CHROMIUM_ROOT" && gclient config --name src https://chromium.googlesource.com/chromium/src.git )
fi

if [[ ! -d "$CHROMIUM_SRC/.git" ]]; then
  step "fetch --nohistory android"
  ( cd "$CHROMIUM_ROOT" && fetch --nohistory android )
else
  step "gclient sync (existing checkout)"
  ( cd "$CHROMIUM_ROOT" && gclient sync --nohistory --delete_unversioned_trees )
fi

step "source state"
( cd "$CHROMIUM_SRC" && git log --oneline -1 && cat chrome/VERSION )
log "done. next: scripts/chromium/build.sh"
