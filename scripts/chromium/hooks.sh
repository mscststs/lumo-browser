#!/usr/bin/env bash
# Install host build dependencies (apt) and run DEPS hooks (clang, ndk, sysroot).
#
#   scripts/chromium/deps.sh          # apt deps (sudo)
#   scripts/chromium/hooks.sh         # gclient runhooks
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

MODE="${1:-hooks}"
[[ -d "$CHROMIUM_SRC" ]] || die "missing $CHROMIUM_SRC"

case "$MODE" in
  apt)
    step "install-build-deps.sh --android"
    ( cd "$CHROMIUM_SRC" && sudo ./build/install-build-deps.sh --android --no-prompt --no-chromeos-fonts )
    ;;
  hooks)
    step "gclient runhooks"
    ( cd "$CHROMIUM_ROOT" && gclient runhooks )
    step "toolchain check"
    missing=0
    for p in \
      third_party/llvm-build/Release+Asserts/bin/clang \
      third_party/android_toolchain/ndk \
      third_party/android_sdk/public \
      third_party/rust-toolchain \
      build/linux/debian_bullseye_amd64-sysroot ; do
      if [[ -e "$CHROMIUM_SRC/$p" ]]; then
        log "ok   $p"
      else
        warn "MISS $p"
        missing=1
      fi
    done
    (( missing == 0 )) || die "toolchain incomplete: run scripts/chromium/cipd-deps.sh and scripts/chromium/toolchain.sh"
    ;;
  *) die "usage: $0 [apt|hooks]" ;;
esac
