#!/usr/bin/env bash
# Print the GN args for a build config. Single source of truth for build.sh and
# fix-missing-deps.sh.
#
#   scripts/chromium/args.sh a|b
#
# FAST=1 (default) drops ThinLTO/symbols: ~2x faster, for on-device iteration.
set -euo pipefail
CONFIG="${1:-a}"
FAST="${FAST:-1}"

case "$CONFIG" in
  a) DESKTOP_ANDROID=true;  EXT_CORE=false ;;
  b) DESKTOP_ANDROID=false; EXT_CORE=true  ;;
  *) echo "unknown config '$CONFIG' (use a|b)" >&2; exit 1 ;;
esac

if [[ "$FAST" == "1" ]]; then OFFICIAL=false; SYMBOLS=0; else OFFICIAL=true; SYMBOLS=1; fi

cat <<EOF
target_os = "android"
target_cpu = "arm64"
is_debug = false
is_official_build = $OFFICIAL
is_component_build = false
symbol_level = $SYMBOLS
is_desktop_android = $DESKTOP_ANDROID
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

if [[ "$EXT_CORE" == "true" ]]; then
  # config b: keep the mobile (non-desktop-android) build but compile the
  # extension core + Android extension UI (internal impls are gated on
  # enable_extensions_core only, see chrome/android/BUILD.gn:1043).
  echo 'enable_desktop_android_extensions = true'
fi


