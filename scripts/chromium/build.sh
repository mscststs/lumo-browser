#!/usr/bin/env bash
# Build the browser APK. Incremental: siso reuses the tree in OUT_DIR, so a
# patch that touches one Java file costs ~2 min and one C++ file ~25 s
# (measurements and the iteration model: docs/05-build.md).
#
#   scripts/chromium/build.sh [a|b]     config a = is_desktop_android (upstream UI)
#                                       config b = android + extension core (product target)
#
# Env: JOBS (default nproc), FAST (default 1), OUT_DIR (default out/lumo-<config>[-rel]),
#      TARGET (default chrome_public_apk), SKIP_BRAND=1, SKIP_PATCHES=1
#
# One out dir per flavor: FAST changes is_official_build, which invalidates
# nearly every object. Never share an out dir between FAST=0 and FAST=1.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

START=$(date +%s)
CONFIG="${1:-a}"
FAST="${FAST:-1}"
JOBS="${JOBS:-$(nproc)}"
TARGET="${TARGET:-chrome_public_apk}"

[[ -d "$CHROMIUM_SRC" ]] || die "missing $CHROMIUM_SRC (run scripts/chromium/fetch.sh)"

case "$CONFIG" in
  a) DESKTOP_ANDROID=true;  EXT_CORE=false ;;
  b) DESKTOP_ANDROID=false; EXT_CORE=true  ;;
  *) die "unknown config '$CONFIG' (use a|b)" ;;
esac

if [[ "$CONFIG" == "b" ]]; then
  warn "config b 被上游 gn 断言阻塞（docs/05-build.md §3），不要用 build.sh b 排全量；"
  warn "现在继续只会得到同样的 gn gen 错误（约 30 s 内失败，不会浪费数小时）。"
fi

# --- build tree -------------------------------------------------------------
# Flavor -> out dir mapping lives in common.sh (shared with cache.sh and
# fix-missing-deps.sh); explicit OUT_DIR always wins.
[[ -n "${OUT_DIR:-}" ]] || OUT_DIR="$(resolve_out_dir "$CONFIG" "$FAST")"

if [[ -d "$CHROMIUM_SRC/$OUT_DIR" ]] && [[ -f "$CHROMIUM_SRC/$OUT_DIR/args.gn" ]]; then
  log "incremental into $OUT_DIR"
else
  warn "new build tree $OUT_DIR: this is a from-scratch build (hours, ~10-20G)"
fi

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  log "dry run: config=$CONFIG FAST=$FAST out=$OUT_DIR target=$TARGET apk_out=$APK_OUT"
  exit 0
fi

# --- patches / signing / branding -------------------------------------------
if [[ "${SKIP_PATCHES:-0}" != "1" ]]; then
  step "applying patches"
  "$REPO_ROOT/scripts/chromium/apply-patches.sh" "$CHROMIUM_SRC"
fi

step "signing key"
"$REPO_ROOT/scripts/chromium/keys.sh" install

if [[ "${SKIP_BRAND:-0}" != "1" ]]; then
  step "branding"
  "$REPO_ROOT/scripts/chromium/brand.sh"
fi

# --- gn / siso --------------------------------------------------------------
step "gn gen ($OUT_DIR, config=$CONFIG, FAST=$FAST)"
GN_ARGS="$(FAST="$FAST" "$REPO_ROOT/scripts/chromium/args.sh" "$CONFIG")"
( cd "$CHROMIUM_SRC" && gn gen "$OUT_DIR" --args="$GN_ARGS" )

step "ninja ($TARGET, jobs=$JOBS)"
( cd "$CHROMIUM_SRC" && autoninja -C "$OUT_DIR" -j "$JOBS" "$TARGET" )

# --- archive ---------------------------------------------------------------
step "archive APK"
mkdir -p "$APK_OUT"
APK_PATH="$CHROMIUM_SRC/$OUT_DIR/apks/ChromePublic.apk"
if [[ ! -f "$APK_PATH" ]]; then
  APK_PATH="$(ls "$CHROMIUM_SRC/$OUT_DIR"/apks/*.apk 2>/dev/null | grep -v -e Test -e Monochrome | head -1 || true)"
fi
[[ -n "$APK_PATH" && -f "$APK_PATH" ]] || die "APK not found under $CHROMIUM_SRC/$OUT_DIR/apks"
# Skip the 350MB copy when the APK is byte-identical to the last one (common
# when iterating on scripts/verify only). cp of an unchanged APK used to add one
# full copy per invocation.
LATEST="$APK_OUT/lumo-latest.apk"
if [[ -f "$LATEST" ]] && cmp -s "$APK_PATH" "$LATEST"; then
  log "apk unchanged: $(readlink -f "$LATEST" | xargs basename)"
else
  DEST="$APK_OUT/lumo-$CONFIG-$(date +%Y%m%d-%H%M).apk"
  cp "$APK_PATH" "$DEST"
  ln -sf "$(basename "$DEST")" "$LATEST"
  log "apk: $DEST ($(du -h "$DEST" | cut -f1))"
fi
"$REPO_ROOT/scripts/chromium/keys.sh" status | sed 's/^/  /'

log "done in $(( $(date +%s) - START ))s (config=$CONFIG FAST=$FAST out=$OUT_DIR)"
