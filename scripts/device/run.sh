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
  EXT_ROOT="/sdcard/Android/data/$PRODUCT_PKG/files/ext"
  CMDLINE="chrome --load-extension=$EXT_ROOT/lumo,$EXT_ROOT/lumo-userscript-manager $FLAGS"
  # Write as the shell user: /data/local/tmp is shell-writable, and going through `su -c`
# mangles the embedded newline/quoting (flags ended up concatenated with "n").
D shell "printf '%s\n' '$CMDLINE' > /data/local/tmp/chrome-command-line; chmod 644 /data/local/tmp/chrome-command-line"
  DR "am set-debug-app --persistent $PRODUCT_PKG" || true
fi
launch_browser
wait_focus 60 || warn "browser not foreground"
sleep 5
shot "$REPO_ROOT/artifacts/shots/run-$(date +%H%M%S).png"
log "pid: $(D shell pidof "$PRODUCT_PKG" | tr -d '\r')"
