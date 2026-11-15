#!/usr/bin/env bash
# Fetch a repo subdirectory from chromium/src at the pinned tag, using the
# googlesource `+archive` endpoint (works through the proxy; no git needed).
#
#   scripts/chromium/fetch-tree.sh third_party/androidx/local_modifications
#   CHROMIUM_TAG=refs/tags/160.0.8157.0 scripts/chromium/fetch-tree.sh <dir>
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
[[ -d "$CHROMIUM_SRC" ]] || die "missing $CHROMIUM_SRC"

REL="${1:?subdirectory relative to src, e.g. third_party/androidx/local_modifications}"
REL="${REL%/}"
TAG="${CHROMIUM_TAG:-refs/tags/160.0.8157.0}"
URL="https://chromium.googlesource.com/chromium/src/+archive/$TAG/$REL.tar.gz"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
log "fetch tree $REL@$TAG"
curl -sSL --retry 10 --retry-delay 3 ${LUMO_CURL_PROXY:+-x "$LUMO_CURL_PROXY"} -o "$tmp/tree.tar.gz" "$URL" \
  || die "download failed: $URL"
[[ -s "$tmp/tree.tar.gz" ]] || die "empty archive: $URL"
mkdir -p "$CHROMIUM_SRC/$REL"
tar -xzf "$tmp/tree.tar.gz" -C "$CHROMIUM_SRC/$REL"
log "ok: $REL ($(find "$CHROMIUM_SRC/$REL" -type f | wc -l) files)"
