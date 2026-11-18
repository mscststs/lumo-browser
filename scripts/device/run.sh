#!/usr/bin/env bash
# One-shot: install the newest APK, stage extensions, launch, screenshot.
#
#   scripts/device/run.sh [apk] [extra chrome flags...]
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
need_device

APK="${1:-$APK_OUT/lumo-latest.apk}"
shift || true
FLAGS="${*:-}"

"$REPO_ROOT/scripts/device/install.sh" "$APK" | tail -2
"$REPO_ROOT/scripts/device/ext-install.sh" | tail -2

step "launch"
if [[ -n "$FLAGS" ]]; then
  # Extra flags are re-pushed through the single composer so the command line
  # stays one string (see scripts/chromium/flags.sh).
  # shellcheck disable=SC2086
  "$REPO_ROOT/scripts/chromium/flags.sh" push $FLAGS | tail -2
fi
launch_browser
wait_focus 60 || warn "browser not foreground"
sleep 5
shot "$REPO_ROOT/artifacts/shots/run-$(date +%H%M%S).png"
log "pid: $(D shell pidof "$PRODUCT_PKG" | tr -d '\r')"
