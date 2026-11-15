#!/usr/bin/env bash
# Install the CIPD-hosted third_party deps that the official tarball omits.
#
# Why: `gclient sync` is unusable on this network (chromium/src advertises ~1M
# refs, so ls-remote never finishes) and release tarballs skip `dep_type: cipd`
# entries. The table is generated from the checkout's DEPS so it stays correct
# when Chromium is bumped.
#
#   scripts/chromium/cipd-deps.sh            # install missing roots
#   scripts/chromium/cipd-deps.sh --all      # re-ensure every root
#
# Requires network access to chrome-infra-packages.appspot.com (CIPD).
# Set LUMO_PROXY=http://127.0.0.1:7890 when DNS for that host is unreliable.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
[[ -d "$CHROMIUM_SRC" ]] || die "missing $CHROMIUM_SRC"
CIPD="$DEPOT_TOOLS/cipd"
[[ -x "$CIPD" ]] || die "cipd not found in depot_tools"
[[ -n "${LUMO_PROXY:-}" ]] && export HTTPS_PROXY="$LUMO_PROXY" HTTP_PROXY="$LUMO_PROXY"

TABLE="$(mktemp)"
trap 'rm -f "$TABLE"' EXIT
python3 "$REPO_ROOT/tools/gen_cipd_table.py" "$CHROMIUM_SRC" > "$TABLE"

only_missing=1
[[ "${1:-}" == "--all" ]] && only_missing=0

# Skip entries that exist only for orderfile/PGO or emulator-only workflows.
is_skippable() {
  case "$1" in
    *orderfiles*) return 0 ;;
    *cts_archive*) return 0 ;;
    *robolectric*) return 0 ;;
    third_party/android_sdk/public|chromium/third_party/android_sdk/public/emulator) return 0 ;;
  esac
  return 1
}

while IFS='|' read -r root pkg ver; do
  [[ -z "$root" ]] && continue
  [[ -z "$ver" ]] && { warn "skip (no pinned version): $root <- $pkg"; continue; }
  is_skippable "$root" && continue

  target="$CHROMIUM_SRC/$root"
  if [[ $only_missing -eq 1 && -d "$target" ]] && [[ -n "$(ls -A "$target" 2>/dev/null)" ]]; then
    log "skip (present): $root"
    continue
  fi
  log "ensure $root <- $pkg@$ver"
  tmp="$(mktemp)"; printf '%s %s\n' "$pkg" "$ver" > "$tmp"
  "$CIPD" ensure -log-level warning -root "$target" -ensure-file "$tmp" || die "cipd ensure failed: $pkg"
  rm -f "$tmp"
done < "$TABLE"

# --- layout fixups ---------------------------------------------------------
# Some packages ship a BUILD.gn at their root plus a `libs/` tree, while GN
# expects the BUILD.gn one directory up and `.info` files under `committed/`.
fixup() { # fixup <root>
  local root="$1" dir="$CHROMIUM_SRC/$1"
  [[ -d "$dir" ]] || return 0
  if [[ -f "$dir/BUILD.gn" && ! -f "$(dirname "$dir")/BUILD.gn" ]]; then
    cp "$dir/BUILD.gn" "$(dirname "$dir")/BUILD.gn"
    log "fixup: copied $root/BUILD.gn to parent"
  fi
  if [[ ! -e "$dir/committed" && -d "$dir/libs" ]]; then
    ln -sfn "$(basename "$dir")" "$(dirname "$dir")/committed"
    log "fixup: linked $(dirname "$root")/committed -> $(basename "$root")"
  fi
}
fixup third_party/androidx/cipd
fixup third_party/android_deps/cipd

step "results"
for d in third_party/android_toolchain/ndk third_party/android_sdk/public \
         third_party/android_deps/cipd third_party/androidx/cipd \
         third_party/kotlinc/current third_party/jdk/current; do
  n=$(ls -A "$CHROMIUM_SRC/$d" 2>/dev/null | wc -l)
  printf '  %-46s %s entries\n' "$d" "$n"
done
