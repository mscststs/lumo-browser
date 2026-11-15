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

step "gn gen ($OUT_DIR, config=$CONFIG)"
GN_ARGS=$(cat <<EOF
target_os = "android"
target_cpu = "arm64"
is_debug = false
is_official_build = true
is_component_build = false
symbol_level = 1
is_desktop_android = $DESKTOP_ANDROID
enable_desktop_android_extensions = $EXT_CORE
disable_fieldtrial_testing_config = true
proprietary_codecs = true
ffmpeg_branding = "Chrome"
enable_arcore = false
enable_vr = false
enable_openxr = false
enable_cardboard = false
enable_remoting = false
enable_reporting = false
google_api_key = "x"
google_default_client_id = "x"
google_default_client_secret = "x"
use_rtti = false
icu_use_data_file = true
include_both_v8_snapshots = false
EOF
)
if [[ "$DESKTOP_ANDROID" == "true" ]]; then
  # Desktop-android builds ship window management; keep ARCORE/VR off.
  GN_ARGS+=$'\nuse_login_database_as_backend = true'
fi

( cd "$CHROMIUM_SRC" && gn gen "$OUT_DIR" --args="$GN_ARGS" )

step "ninja ($TARGET, jobs=$JOBS)"
( cd "$CHROMIUM_SRC" && autoninja -C "$OUT_DIR" -j "$JOBS" "$TARGET" )

step "archive APK"
mkdir -p "$APK_OUT"
APK_PATH="$(ls -t "$CHROMIUM_SRC/$OUT_DIR"/apks/*.apk 2>/dev/null | head -1 || true)"
[[ -n "$APK_PATH" ]] || die "APK not found under $CHROMIUM_SRC/$OUT_DIR/apks"
DEST="$APK_OUT/lumo-$CONFIG-$(date +%Y%m%d-%H%M).apk"
cp "$APK_PATH" "$DEST"
ln -sf "$(basename "$DEST")" "$APK_OUT/lumo-latest.apk"
log "apk: $DEST ($(du -h "$DEST" | cut -f1))"
