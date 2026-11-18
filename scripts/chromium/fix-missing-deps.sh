#!/usr/bin/env bash
# Iteratively fetch DEPS git deps that the official tarball omitted, driven by
# `gn gen` errors ("Unable to load //<path>/BUILD.gn").
#
#   scripts/chromium/fix-missing-deps.sh [config]
set -uo pipefail
source "$(dirname "$0")/../lib/common.sh"
[[ -d "$CHROMIUM_SRC" ]] || die "missing $CHROMIUM_SRC"

CONFIG="${1:-a}"
[[ -n "${OUT_DIR:-}" ]] || OUT_DIR="$(resolve_out_dir "$CONFIG" "${FAST:-1}")"
MAX=40

for i in $(seq 1 "$MAX"); do
  log "gn gen attempt $i"
  err="$( ( cd "$CHROMIUM_SRC" && gn gen "$OUT_DIR" --args="$(FAST="${FAST:-1}" "$REPO_ROOT/scripts/chromium/args.sh" "$CONFIG")" ) 2>&1 )"
  if [[ $? -eq 0 ]]; then
    log "gn gen ok"
    exit 0
  fi
  rel="$(sed -n 's#.*Unable to load ".*/src/\([^"]*\)/BUILD\.gn".*#\1#p' <<<"$err" | head -1)"
  if [[ -z "$rel" ]]; then
    printf '%s\n' "$err" | tail -20 >&2
    die "gn gen failed for a reason that is not a missing DEPS path"
  fi
  log "missing dep: $rel"
  read -r url rev < <(python3 "$REPO_ROOT/tools/deps_resolve.py" "$CHROMIUM_SRC" "$rel") || die "cannot resolve $rel in DEPS"
  LUMO_CURL_PROXY="${LUMO_CURL_PROXY:-}" "$REPO_ROOT/scripts/chromium/fetch-dep.sh" "$rel" "$url" "$rev" \
    || die "failed to fetch $rel"
done
die "gave up after $MAX iterations"
