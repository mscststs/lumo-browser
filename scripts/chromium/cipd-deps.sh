#!/usr/bin/env bash
# Fetch the CIPD-hosted third_party deps that the official tarball omits.
#
# Why: `gclient sync` cannot be used here (git smart-HTTP to googlesource is
# unusable on this network), and the release tarball intentionally excludes
# `dep_type: cipd` entries. Without these the Android build fails early.
#
# Versions are pinned to Chromium 160.0.8157.0 (see DEPS @@ the checkout).
# When bumping Chromium, refresh this table from DEPS (the `cipd` blocks whose
# condition contains `checkout_android`).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
[[ -d "$CHROMIUM_SRC" ]] || die "missing $CHROMIUM_SRC"
CIPD="$DEPOT_TOOLS/cipd"
[[ -x "$CIPD" ]] || die "cipd not found in depot_tools"

# root-path | package | version
DEPS_TABLE=$(cat <<'EOF'
third_party/androidx/cipd|chromium/third_party/androidx|toNYDuKhIatHoWl-4GSuk8k_mL7ZcjK7vFnkaEXwOK0C
third_party/jdk/current|chromium/third_party/jdk/linux-amd64|version:2@jdk-25.0.5+8.f32c55fd1a.cr0
third_party/android_toolchain/ndk|chromium/third_party/android_toolchain/android_toolchain/linux-amd64|version:2@30.0.16248370
third_party/android_sdk/public/build-tools/37.0.0|chromium/third_party/android_sdk/public/build-tools/37.0.0/linux|version_37.0.0
third_party/android_sdk/public/emulator|chromium/third_party/android_sdk/public/emulator|9lGp8nTUCRRWGMnI_96HcKfzjnxEJKUcfvfwmA3wXNkC
third_party/android_sdk/public/platform-tools|chromium/third_party/android_sdk/public/platform-tools|qTD9QdBlBf3dyHsN1lJ0RH6AhHxR42Hmg2Ih-Vj4zIEC
third_party/android_sdk/public/platforms/android-37.2|chromium/third_party/android_sdk/public/platforms/android-37.2|AAswZ5rZBFDhMaH4QbKPmVtP4vnjiNUW_zPhdWvNe6wC
third_party/android_sdk/public/cmdline-tools|chromium/third_party/android_sdk/public/cmdline-tools/linux|version:23.0.0
third_party/android_system_sdk/public|chromium/third_party/android_system_sdk/public|QAcOcO9AlzRvhHOaFCxeQAcdO3qiFPwxUHXUIlSbw3kC
third_party/android_deps/autorolled|chromium/third_party/android_deps/autorolled|pjstKgIwKDCCMJPDeqroCroPJy-ObnfaITLMoDxoAC4C
third_party/kotlinc/current|chromium/third_party/kotlinc|KONJL1FlbaajWlp8EaVhvWdfCn9vgR-sXxgXdgB5UzwC
EOF
)

only_missing=1
[[ "${1:-}" == "--all" ]] && only_missing=0

while IFS='|' read -r root pkg ver; do
  [[ -z "$root" ]] && continue
  target="$CHROMIUM_SRC/$root"
  if [[ $only_missing -eq 1 && -d "$target" ]] && [[ -n "$(ls -A "$target" 2>/dev/null)" ]]; then
    log "skip (present): $root"
    continue
  fi
  log "ensure $root <- $pkg@$ver"
  tmp="$(mktemp)"; printf '%s %s\n' "$pkg" "$ver" > "$tmp"
  "$CIPD" ensure -log-level warning -root "$target" -ensure-file "$tmp" || die "cipd ensure failed: $pkg"
  rm -f "$tmp"
done <<< "$DEPS_TABLE"

step "results"
for d in third_party/android_toolchain/ndk third_party/android_sdk/public third_party/android_system_sdk/public third_party/android_deps/autorolled third_party/kotlinc/current; do
  n=$(ls -A "$CHROMIUM_SRC/$d" 2>/dev/null | wc -l)
  printf '  %-46s %s entries\n' "$d" "$n"
done
