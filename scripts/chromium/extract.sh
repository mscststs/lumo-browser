#!/usr/bin/env bash
# Materialize Chromium source from an official GCS tarball.
#
# Needed because this network cannot use git smart-HTTP against
# chromium.googlesource.com (ls-remote hangs). GCS is reachable at several MB/s.
#
#   scripts/chromium/extract.sh [tarball]
#
# Default tarball: artifacts/src/chromium-<version>.tar.xz
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

TB="${1:-$(ls -t "$REPO_ROOT"/artifacts/src/chromium-*.tar.xz 2>/dev/null | head -1 || true)}"
[[ -n "$TB" && -f "$TB" ]] || die "no tarball found (download: chromium-browser-official/chromium-<ver>.tar.xz)"
[[ -f "$TB.hashes" ]] || warn "no .hashes file next to tarball; skipping digest check"

if [[ -d "$CHROMIUM_SRC" && -f "$CHROMIUM_SRC/DEPS" ]]; then
  log "source already present: $CHROMIUM_SRC"
else
  step "extract $(basename "$TB") ($(du -h "$TB" | cut -f1))"
  mkdir -p "$CHROMIUM_ROOT"
  INNER="$(tar -tf "$TB" | head -1 | cut -d/ -f1)"
  xz -dc -T0 "$TB" | tar -xf - -C "$CHROMIUM_ROOT"
  [[ -d "$CHROMIUM_ROOT/$INNER" ]] || die "unexpected tarball layout"
  rm -rf "$CHROMIUM_SRC"
  mv "$CHROMIUM_ROOT/$INNER" "$CHROMIUM_SRC"
fi

step "minimal .gclient (managed=False: never sync from googlesource)"
cat > "$CHROMIUM_ROOT/.gclient" <<'EOF'
solutions = [{
  "name": "src",
  "url": "https://chromium.googlesource.com/chromium/src.git",
  "managed": False,
  "custom_deps": {},
  "custom_vars": {},
}]
target_os = ["android"]
EOF

{
  echo "src: $(cd "$CHROMIUM_SRC" && pwd)"
  echo "version: $(cat "$CHROMIUM_SRC/chrome/VERSION" | tr '\n' ' ')"
  echo "size: $(du -sh "$CHROMIUM_SRC" | cut -f1)"
} | sed 's/^/  /'
log "next: scripts/chromium/hooks.sh"
