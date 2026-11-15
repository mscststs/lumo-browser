#!/usr/bin/env bash
# Launch the browser and wait until it owns the window.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
need_device
launch_browser
wait_focus 45 && log "browser foreground" || warn "browser did not reach foreground in 45s"
