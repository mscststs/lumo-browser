#!/usr/bin/env bash
# Stage the two reference MV3 extensions onto the device and register them.
#
#   scripts/device/ext-install.sh [--build]
#
# Mechanism: extensions live in the app's *external* files dir (readable by the
# app, writable over adb, no SELinux fight) and are loaded through the Chrome
# command line file. Requires the `command-line-always` patch in patches/.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
need_device

BUILD=0
[[ "${1:-}" == "--build" ]] && BUILD=1

build_ext() { # build_ext <dir> <name>
  local dir="$1" name="$2"
  local out="$dir/.output/chrome-mv3"
  if [[ $BUILD -eq 1 || ! -d "$out" ]]; then
    step "build $name extension"
    ( cd "$dir" && npm run build )
  fi
  [[ -f "$out/manifest.json" ]] || die "$name build missing: $out/manifest.json"
  echo "$out"
}

LUMO_OUT="$(build_ext "$EXT_LUMO_DIR" lumo)"
US_OUT="$(build_ext "$EXT_US_DIR" lumo-userscript-manager)"

EXT_ROOT="/sdcard/Android/data/$PRODUCT_PKG/files/ext"
step "push extensions -> $EXT_ROOT"
D shell mkdir -p "$EXT_ROOT"
D shell rm -rf "$EXT_ROOT/lumo" "$EXT_ROOT/lumo-userscript-manager"
D push "$LUMO_OUT" "$EXT_ROOT/lumo" >/dev/null
D push "$US_OUT" "$EXT_ROOT/lumo-userscript-manager" >/dev/null

step "register via chrome command line"
DR "cat > /data/local/tmp/chrome-command-line <<'EOL'
chrome --load-extension=$EXT_ROOT/lumo --load-extension=$EXT_ROOT/lumo-userscript-manager
EOL
chmod 644 /data/local/tmp/chrome-command-line; am force-stop $PRODUCT_PKG"
log "extensions staged; relaunch the app (scripts/device/launch.sh)"
