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
# shellcheck source=scripts/lib/signing.env
source "$(dirname "$0")/../lib/signing.env"

case "$CONFIG" in
  a) DESKTOP_ANDROID=true;  EXT_CORE=false ;;
  b) DESKTOP_ANDROID=false; EXT_CORE=true  ;;
  *) echo "unknown config '$CONFIG' (use a|b)" >&2; exit 1 ;;
esac

if [[ "$FAST" == "1" ]]; then
  OFFICIAL=false; SYMBOLS=0; THIN_LTO=false
else
  # Release config. NOTE: non-official Android builds enable UBSan "hardening"
  # traps (array-bounds/return/unreachable) and DCHECK_ALWAYS_ON, which abort
  # silently in the GPU process on some drivers. Official builds are required
  # for a runnable device build.
  OFFICIAL=true; SYMBOLS=0; THIN_LTO=${THIN_LTO:-false}
fi

cat <<EOF
target_os = "android"
target_cpu = "arm64"
is_debug = false
is_official_build = $OFFICIAL
use_thin_lto = $THIN_LTO
# The official tarball ships no PGO profiles (they come from a DEPS GCS entry).
chrome_pgo_phase = 0
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
# Product identity (Lumo Browser).
chrome_public_manifest_package = "dev.lumo.browser"
EOF

# Signing: the repo-tracked dev key (keys/README.md). keys.sh stages a copy
# inside the checkout because GN cannot reference paths outside the source root.
# These args only affect the apk packaging steps, so changing them re-signs but
# never recompiles.
cat <<KEYEOF
android_keystore_path = "$LUMO_KEY_GN_DIR/lumo-dev.jks"
android_keystore_name = "$LUMO_KEY_ALIAS"
android_keystore_password = "$LUMO_KEY_PASSWORD"
KEYEOF

if [[ "$EXT_CORE" == "true" ]]; then
  # config b: keep the mobile (non-desktop-android) build but compile the
  # extension core + Android extension UI (internal impls are gated on
  # enable_extensions_core only, see chrome/android/BUILD.gn:1043).
  echo 'enable_desktop_android_extensions = true'
fi


