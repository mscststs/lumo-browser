#!/usr/bin/env bash
# Install the built APK on the (rooted) device.
#
#   scripts/device/install.sh [apk]
#
# MIUI blocks `adb install` ("canceled by user"); installing through `su` with
# an explicit installer package works on this ROM, so we try that first.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
need_device

APK="${1:-$APK_OUT/lumo-latest.apk}"
[[ -f "$APK" ]] || die "apk not found: $APK"

REMOTE="/data/local/tmp/lumo-install.apk"
step "push $(du -h "$APK" | cut -f1) -> $REMOTE"
D push "$APK" "$REMOTE" >/dev/null

step "install on $DEVICE_SERIAL"
OUT="$(DR "pm install -r -g -d -i com.miui.packageinstaller $REMOTE" 2>&1 || true)"
if ! grep -q "Success" <<<"$OUT"; then
  warn "su pm install failed: $OUT"
  OUT="$(D install -r -g "$APK" 2>&1 || true)"
  grep -q "Success" <<<"$OUT" || die "install failed: $OUT"
fi
DR "rm -f $REMOTE" || true
log "installed $(D shell pm list packages | grep -c . ) packages total; target: $PRODUCT_PKG"
D shell pm path "$PRODUCT_PKG" || die "$PRODUCT_PKG not installed"
