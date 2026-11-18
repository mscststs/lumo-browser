#!/usr/bin/env bash
# Snapshot / restore the build tree, and record what a kernel binary was built
# from. The tree in out/<dir> *is* the compile cache: siso keeps per-action
# state there, so a restored tree turns a multi-hour rebuild into a 25s-2min
# incremental build.
#
#   scripts/chromium/cache.sh manifest [out_dir]     # kernel identity -> artifacts/cache/
#   scripts/chromium/cache.sh snapshot [out_dir]     # out_dir -> artifacts/cache/*.tar.zst
#   scripts/chromium/cache.sh restore <archive> [out_dir]
#   scripts/chromium/cache.sh list
#
# Restoring only works on a checkout that still matches the archive: same
# Chromium tarball, same depot_tools/clang CIPD versions, same absolute paths
# ($HOME/chromium/src). A Chromium upgrade invalidates the tree by design.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

CACHE_DIR="$REPO_ROOT/artifacts/cache"
default_out() { resolve_out_dir a 0; }

usage() { die "usage: cache.sh [manifest|snapshot|restore|list] ..."; }

chromium_version() {
  local f="$CHROMIUM_SRC/chrome/VERSION"
  [[ -f "$f" ]] || { echo unknown; return; }
  # shellcheck disable=SC1090
  ( set -a; . "$f" 2>/dev/null || true; set +a
    printf '%s.%s.%s.%s' "${MAJOR:-?}" "${MINOR:-?}" "${BUILD:-?}" "${PATCH:-?}" )
}

clang_version() {
  local c="$CHROMIUM_SRC/third_party/llvm-build/Release+Asserts/bin/clang"
  [[ -x "$c" ]] || { echo unknown; return; }
  "$c" --version 2>/dev/null | head -1
}

depot_tools_rev() {
  local d="$DEPOT_TOOLS"
  [[ -d "$d/.git" ]] || { echo unknown; return; }
  git -C "$d" rev-parse --short HEAD 2>/dev/null || echo unknown
}

cmd_manifest() {
  local out="${1:-$(default_out)}"
  local args_gn="$CHROMIUM_SRC/$out/args.gn"
  local apk="$CHROMIUM_SRC/$out/apks/ChromePublic.apk"
  mkdir -p "$CACHE_DIR"
  local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
  local file="$CACHE_DIR/kernel-$stamp.txt"

  {
    printf 'lumo kernel manifest\n'
    printf 'created     : %s\n' "$(date -Is)"
    printf 'chromium    : %s\n' "$(chromium_version)"
    printf 'src         : %s\n' "$CHROMIUM_SRC"
    printf 'out dir     : %s\n' "$out"
    printf 'clang       : %s\n' "$(clang_version)"
    printf 'depot_tools : %s\n' "$(depot_tools_rev)"
    printf 'args.gn sha : %s\n' "$([[ -f "$args_gn" ]] && sha256sum "$args_gn" | cut -d' ' -f1 || echo missing)"
    printf 'gn args     :\n'
    [[ -f "$args_gn" ]] && sed 's/^/  /' "$args_gn"
    printf 'patches     :\n'
    local p
    for p in "$REPO_ROOT"/patches/[0-9][0-9][0-9][0-9]-*.patch; do
      [[ -f "$p" ]] || continue
      printf '  %s  %s\n' "$(sha256sum "$p" | cut -d' ' -f1)" "$(basename "$p")"
    done
    if [[ -f "$apk" ]]; then
      printf 'apk         : %s\n' "$apk"
      printf 'apk sha256  : %s\n' "$(sha256sum "$apk" | cut -d' ' -f1)"
      printf 'apk size    : %s\n' "$(du -h "$apk" | cut -f1)"
    fi
    printf 'signing     : dev key, keys/lumo-dev.jks (debug-only, see keys/README.md)\n'
  } | tee "$file"

  log "manifest: $file"
}

cmd_snapshot() {
  local out="${1:-$(default_out)}"
  [[ -d "$CHROMIUM_SRC/$out" ]] || die "no build tree: $CHROMIUM_SRC/$out"
  mkdir -p "$CACHE_DIR"
  local name; name="$(basename "$out")-$(date +%Y%m%d-%H%M)"
  local archive
  if command -v zstd >/dev/null; then
    archive="$CACHE_DIR/out-$name.tar.zst"
    step "snapshot $out -> $archive (zstd -3)"
    tar -C "$CHROMIUM_SRC/out" -cf - "$(basename "$out")" | zstd -T0 -3 -q -o "$archive"
  else
    archive="$CACHE_DIR/out-$name.tar.gz"
    step "snapshot $out -> $archive (gzip; install zstd for ~2x speed)"
    tar -C "$CHROMIUM_SRC/out" -czf "$archive" "$(basename "$out")"
  fi
  log "archive: $archive ($(du -h "$archive" | cut -f1))"
  log "restore with: scripts/chromium/cache.sh restore $archive $out"
}

cmd_restore() {
  local archive="${1:-}"; [[ -f "$archive" ]] || usage
  local want="${2:-}"
  want="${want#out/}"

  # Peek at the archived top-level directory so a renamed restore still lands in
  # the tree the archive actually contains.
  local top
  case "$archive" in
    *.tar.zst) command -v zstd >/dev/null || die "zstd not installed"
               top="$(zstd -dc "$archive" | tar -tf - | head -1 | cut -d/ -f1)" ;;
    *.tar.gz)  top="$(tar -tzf "$archive" | head -1 | cut -d/ -f1)" ;;
    *) die "unknown archive type: $archive" ;;
  esac
  [[ -n "$top" ]] || die "cannot read archive listing: $archive"

  local target="${want:-$top}"
  local dest="$CHROMIUM_SRC/out/$target"
  if [[ -d "$dest" ]] && [[ -n "$(ls -A "$dest" 2>/dev/null)" ]]; then
    warn "$dest already exists; refusing to overwrite (remove it or pass another out dir)"
    return 1
  fi

  step "restore $archive -> $dest"
  mkdir -p "$CHROMIUM_SRC/out"
  case "$archive" in
    *.tar.zst) zstd -dc "$archive" | tar -C "$CHROMIUM_SRC/out" -xf - ;;
    *.tar.gz)  tar -C "$CHROMIUM_SRC/out" -xzf "$archive" ;;
  esac
  if [[ "$target" != "$top" ]]; then
    [[ -e "$CHROMIUM_SRC/out/$top" ]] || die "archive did not contain $top"
    mv "$CHROMIUM_SRC/out/$top" "$dest"
  fi
  log "restored $dest"
  log "next build reuses it: scripts/chromium/build.sh $(echo "$target" | sed -E 's/^lumo-//; s/-rel$//')  (or OUT_DIR=out/$target)"
}

cmd_list() {
  [[ -d "$CACHE_DIR" ]] || { log "no snapshots in $CACHE_DIR"; return; }
  ls -lh "$CACHE_DIR" | sed 's/^/  /'
}

case "${1:-}" in
  manifest) shift; cmd_manifest "$@" ;;
  snapshot) shift; cmd_snapshot "$@" ;;
  restore)  shift; cmd_restore "$@" ;;
  list)     cmd_list ;;
  *) usage ;;
esac
