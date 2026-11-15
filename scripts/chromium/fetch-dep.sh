#!/usr/bin/env bash
# Materialize one DEPS git dependency from the googlesource `+archive` endpoint.
#
# Needed because the official tarball omits `checkout_android` deps, and
# `gclient sync` is unusable (chromium/src has ~1M refs; ls-remote never ends).
# The archive endpoint needs only a 40-char revision and is fast (<1MB here).
#
#   scripts/chromium/fetch-dep.sh third_party/libunwindstack_tmp \
#       https://chromium.googlesource.com/chromium/src/third_party/libunwindstack.git \
#       f1d37918397daa1afd6f21de6e6a4c5ab0bee53b
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
[[ -d "$CHROMIUM_SRC" ]] || die "missing $CHROMIUM_SRC"

REL="${1:?path relative to src, e.g. third_party/foo}"
URL="${2:?git url}"
REV="${3:?revision (40 chars)}"
DEST="$CHROMIUM_SRC/$REL"

if [[ -d "$DEST" && -n "$(ls -A "$DEST" 2>/dev/null)" ]]; then
  log "present: $REL"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
archive="${URL%.git}.git/+archive/$REV.tar.gz"
log "fetch $(basename "$REL")@${REV:0:10}"
curl -sSL --retry 10 --retry-delay 3 ${LUMO_CURL_PROXY:+-x "$LUMO_CURL_PROXY"} \
  -o "$tmp/dep.tar.gz" "$archive" || die "download failed: $archive"
[[ -s "$tmp/dep.tar.gz" ]] || die "empty archive: $archive"
mkdir -p "$DEST"
tar -xzf "$tmp/dep.tar.gz" -C "$DEST"
log "ok: $REL ($(du -sh "$DEST" | cut -f1))"
