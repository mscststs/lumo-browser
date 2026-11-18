#!/usr/bin/env bash
# Stage / inspect the repo-tracked dev signing key (keys/README.md).
#
#   scripts/chromium/keys.sh install   # copy into the checkout (build.sh does this)
#   scripts/chromium/keys.sh status    # alias, validity, certificate fingerprint
#
# Why a copy: GN resolves paths relative to the Chromium source root only, so
# `android_keystore_path` must be a //-relative path that exists inside
# $CHROMIUM_SRC. The file in this repo stays the single source of truth.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

KEY_FILE="${LUMO_KEY_FILE:-$REPO_ROOT/keys/lumo-dev.jks}"
KEY_DIR="$CHROMIUM_SRC/lumo-signing"
KEY_DST="$KEY_DIR/lumo-dev.jks"

keytool_bin() {
  local vendored="$CHROMIUM_SRC/third_party/jdk/current/bin/keytool"
  if [[ -x "$vendored" ]]; then printf '%s' "$vendored"; return 0; fi
  command -v keytool || die "no keytool (install a JDK or run scripts/chromium/cipd-deps.sh)"
}

cmd_install() {
  [[ -f "$KEY_FILE" ]] || die "missing dev key: $KEY_FILE (see keys/README.md)"

  # The certificate itself is enough to catch a truncated/corrupt file.
  "$(keytool_bin)" -list -keystore "$KEY_FILE" -storepass "$LUMO_KEY_PASSWORD" \
    -alias "$LUMO_KEY_ALIAS" >/dev/null 2>&1 \
    || die "cannot read $KEY_FILE with alias '$LUMO_KEY_ALIAS' (see keys/README.md)"

  mkdir -p "$KEY_DIR"
  if [[ -f "$KEY_DST" ]] && cmp -s "$KEY_FILE" "$KEY_DST"; then
    log "keystore already staged: $KEY_DST"
  else
    install -m 600 "$KEY_FILE" "$KEY_DST"
    log "staged keystore: $KEY_DST"
  fi
}

cmd_status() {
  [[ -f "$KEY_FILE" ]] || die "missing dev key: $KEY_FILE"
  local out
  out="$("$(keytool_bin)" -list -v -keystore "$KEY_FILE" \
    -storepass "$LUMO_KEY_PASSWORD" -alias "$LUMO_KEY_ALIAS" 2>&1)" \
    || die "cannot read $KEY_FILE: $out"
  # keytool indents most fields ("\t SHA256: ..."), so allow leading whitespace.
  printf '%s\n' "$out" | grep -E '^[[:space:]]*(Alias name|Owner|Valid from|SHA256):' | sed 's/^[[:space:]]*/  /'
  printf '  file    : %s\n' "$KEY_FILE"
  printf '  staged  : %s\n' "$([[ -f "$KEY_DST" ]] && echo "$KEY_DST" || echo '(not staged yet)')"
  printf '  scope   : DEBUG / self-test builds of dev.lumo.browser ONLY (keys/README.md)\n'
}

case "${1:-install}" in
  install) cmd_install ;;
  status)  cmd_status ;;
  *) die "usage: keys.sh [install|status]" ;;
esac
