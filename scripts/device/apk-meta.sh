#!/usr/bin/env bash
# Derive package name / launcher activity from an APK and cache it for other
# scripts (artifacts/apk/meta.env).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
APK="${1:-$APK_OUT/lumo-latest.apk}"
[[ -f "$APK" ]] || die "apk not found: $APK"
AAPT2="${AAPT2:-$CHROMIUM_SRC/third_party/android_sdk/public/build-tools/37.0.0/aapt2}"
[[ -x "$AAPT2" ]] || AAPT2="$(command -v aapt2 || true)"
[[ -x "$AAPT2" ]] || die "aapt2 not found (set AAPT2=...)"

BADGING="$("$AAPT2" dump badging "$APK" 2>/dev/null)"
PKG="$(sed -n "s/^package: name='\([^']*\)'.*/\1/p" <<<"$BADGING" | head -1)"
ACT="$(sed -n "s/^launchable-activity: name='\([^']*\)'.*/\1/p" <<<"$BADGING" | head -1)"
[[ -n "$PKG" ]] || die "cannot read package name"
mkdir -p "$APK_OUT"
cat > "$APK_OUT/meta.env" <<EOM
PRODUCT_PKG=$PKG
MAIN_ACTIVITY=$ACT
APK_PATH=$APK
EOM
log "package: $PKG"
log "activity: ${ACT:-<none>}"
