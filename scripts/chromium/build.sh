#!/usr/bin/env bash
# Build the browser APK.
#
#   scripts/chromium/build.sh [a|b]     config a = is_desktop_android (upstream)
#                                       config b = android + extension core (target)
#
# Env: JOBS (default nproc), OUT_DIR (default out/lumo-<config>)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

CONFIG="${1:-a}"
# FAST=1 -> non-official build (no ThinLTO): ~2x faster, good for functional
# iteration on device. Ship builds use FAST=0.
FAST="${FAST:-1}"
JOBS="${JOBS:-$(nproc)}"
OUT_DIR="${OUT_DIR:-out/lumo-$CONFIG}"
TARGET="${TARGET:-chrome_public_apk}"

[[ -d "$CHROMIUM_SRC" ]] || die "missing $CHROMIUM_SRC (run scripts/chromium/fetch.sh)"

case "$CONFIG" in
  a) DESKTOP_ANDROID=true;  EXT_CORE=false ;;
  b) DESKTOP_ANDROID=false; EXT_CORE=true  ;;
  *) die "unknown config '$CONFIG' (use a|b)" ;;
esac

step "applying patches"
"$REPO_ROOT/scripts/chromium/apply-patches.sh" "$CHROMIUM_SRC"

step "branding"
"$REPO_ROOT/scripts/chromium/brand.sh"

step "gn gen ($OUT_DIR, config=$CONFIG)"
GN_ARGS="$(FAST="$FAST" "$REPO_ROOT/scripts/chromium/args.sh" "$CONFIG")"
( cd "$CHROMIUM_SRC" && gn gen "$OUT_DIR" --args="$GN_ARGS" )

step "ninja ($TARGET, jobs=$JOBS)"
( cd "$CHROMIUM_SRC" && autoninja -C "$OUT_DIR" -j "$JOBS" "$TARGET" )

step "archive APK"
mkdir -p "$APK_OUT"
APK_PATH="$CHROMIUM_SRC/$OUT_DIR/apks/ChromePublic.apk"
if [[ ! -f "$APK_PATH" ]]; then
  APK_PATH="$(ls "$CHROMIUM_SRC/$OUT_DIR"/apks/*.apk 2>/dev/null | grep -v -e Test -e Monochrome | head -1 || true)"
fi
[[ -n "$APK_PATH" && -f "$APK_PATH" ]] || die "APK not found under $CHROMIUM_SRC/$OUT_DIR/apks"
DEST="$APK_OUT/lumo-$CONFIG-$(date +%Y%m%d-%H%M).apk"
cp "$APK_PATH" "$DEST"
ln -sf "$(basename "$DEST")" "$APK_OUT/lumo-latest.apk"
log "apk: $DEST ($(du -h "$DEST" | cut -f1))"
