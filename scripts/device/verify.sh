#!/usr/bin/env bash
# End-to-end device verification: install extensions, launch, collect evidence.
#
#   scripts/device/verify.sh [apk]
#
# Evidence goes to artifacts/verify/<run-id>/ :
#   screen-*.png   ui-*.xml   logcat.txt   probe.json   summary.txt
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
need_device

RUN_ID="$(date +%Y%m%d-%H%M%S)"
OUT="$REPO_ROOT/artifacts/verify/$RUN_ID"
mkdir -p "$OUT"
log "run: $OUT"

# 1) install the browser (optional: pass an apk explicitly)
if [[ -n "${1:-}" ]]; then
  step "install apk"
  "$REPO_ROOT/scripts/device/install.sh" "$1" | tee -a "$OUT/summary.txt"
else
  D shell pm path "$PRODUCT_PKG" >/dev/null 2>&1 || die "$PRODUCT_PKG not installed (run scripts/device/install.sh)"
fi

# 2) stage extensions (probe + the two reference extensions)
step "stage extensions"
EXT_ROOT="/sdcard/Android/data/$PRODUCT_PKG/files/ext"
D shell mkdir -p "$EXT_ROOT"
D shell rm -rf "$EXT_ROOT/probe" "$EXT_ROOT/lumo" "$EXT_ROOT/lumo-userscript-manager"
D push "$REPO_ROOT/tools/probe-extension" "$EXT_ROOT/probe" >/dev/null
D push "$EXT_LUMO_DIR/.output/chrome-mv3" "$EXT_ROOT/lumo" >/dev/null
D push "$EXT_US_DIR/.output/chrome-mv3" "$EXT_ROOT/lumo-userscript-manager" >/dev/null
DR "printf 'chrome --load-extension=%s\n' '$EXT_ROOT/probe,$EXT_ROOT/lumo,$EXT_ROOT/lumo-userscript-manager' > /data/local/tmp/chrome-command-line; chmod 644 /data/local/tmp/chrome-command-line"
DR "am set-debug-app --persistent $PRODUCT_PKG" || true

# 3) launch with a clean log
step "launch"
D logcat -c 2>/dev/null || true
launch_browser
wait_focus 60 || warn "browser not foreground"
sleep 6
shot "$OUT/screen-01-home.png"
ui_dump "$OUT/ui-01-home.xml"

# 4) extensions page
step "extensions page"
if open_extensions_page; then
  sleep 4
  shot "$OUT/screen-02-extensions.png"
  ui_dump "$OUT/ui-02-extensions.xml"
  grep -o 'text="[^"]*"' "$OUT/ui-02-extensions.xml" | sed 's/text="//;s/"$//' | grep -v '^$' \
    > "$OUT/extensions-strings.txt" || true
else
  warn "could not reach chrome://extensions through the menu"
fi

# 5) logcat + probe payload
step "collect logcat"
D logcat -d > "$OUT/logcat.txt" 2>/dev/null || true
python3 - "$OUT" <<'PY'
import json, re, sys
out = sys.argv[1]
raw = open(f'{out}/logcat.txt', encoding='utf-8', errors='ignore').read()
hit = None
for m in re.finditer(r'PROBE_JSON (\{.*\})', raw):
    hit = m.group(1)
if hit:
    try:
        data = json.loads(hit)
    except json.JSONDecodeError:
        data = None
    if data:
        open(f'{out}/probe.json', 'w').write(json.dumps(data, indent=2))
        meta = data.get('meta', {})
        print(f"probe: {meta.get('pass')} pass / {meta.get('fail')} fail / {meta.get('total')} total")
PY

# 6) summary
{
  echo "run=$RUN_ID"
  echo "device=$DEVICE_SERIAL pkg=$PRODUCT_PKG"
  echo "apk=$(D shell dumpsys package "$PRODUCT_PKG" | grep -m1 versionName || true)"
  echo "--- extensions visible:"
  grep -iE "lumo|probe|userscript" "$OUT/extensions-strings.txt" 2>/dev/null || echo "(none)"
  echo "--- sw state:"
  grep -iE "Service Worker" "$OUT/extensions-strings.txt" 2>/dev/null || true
} | tee "$OUT/summary.txt"

step "done"
ls -1 "$OUT"
