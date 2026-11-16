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
# NOTE: the probe is staged under a content-hashed directory so Chrome cannot
# reuse a cached extension script from an older probe build.
PROBE_HASH="$(find "$REPO_ROOT/tools/probe-extension" -type f -exec sha256sum {} + | sort | sha256sum | cut -c1-10)"
PROBE_DIR="$EXT_ROOT/probe-$PROBE_HASH"
D shell rm -rf "$EXT_ROOT"/probe-* "$EXT_ROOT/lumo" "$EXT_ROOT/lumo-userscript-manager"
D push "$REPO_ROOT/tools/probe-extension" "$PROBE_DIR" >/dev/null
D push "$EXT_LUMO_DIR/.output/chrome-mv3" "$EXT_ROOT/lumo" >/dev/null
D push "$EXT_US_DIR/.output/chrome-mv3" "$EXT_ROOT/lumo-userscript-manager" >/dev/null
# Extensions are loaded through the upstream rooted flow: `/data/local/tmp` command line +
# `am set-debug-app` (Chrome's documented non-rooted/debug-app handshake). We deliberately do
# NOT read flags from shared storage — any app with all-files access could otherwise inject
# `--load-extension` / `--remote-debugging-port`.
CMDLINE="chrome --load-extension=$PROBE_DIR,$EXT_ROOT/lumo,$EXT_ROOT/lumo-userscript-manager --no-first-run --disable-fre --no-default-browser-check --remote-debugging-port=9222"
# Write as the shell user: /data/local/tmp is shell-writable, and going through `su -c`
# mangles the embedded newline/quoting (flags ended up concatenated with "n").
D shell "printf '%s\n' '$CMDLINE' > /data/local/tmp/chrome-command-line; chmod 644 /data/local/tmp/chrome-command-line"
D shell "rm -f /sdcard/Android/data/$PRODUCT_PKG/files/chrome-command-line" 2>/dev/null || true
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
  # Only toggle developer mode on if it is currently off (otherwise we would turn it off).
  DEV_MODE="$(python3 "$REPO_ROOT/tools/cdp.py" eval --target "chrome://extensions" --await \
      --expr '(async()=>{const c=await chrome.developerPrivate.getProfileConfiguration();return String(c.inDeveloperMode)})()' 2>/dev/null || echo unknown)"
  if [[ "$DEV_MODE" == "true" ]]; then
    log "developer mode already on"
  else
    tap_switch_near "开发者模式" || tap_text "开发者模式" || tap_text "Developer mode" || true
    sleep 2
  fi
  shot "$OUT/screen-02-extensions.png"
  ui_dump "$OUT/ui-02-extensions.xml"
  grep -o 'text="[^"]*"' "$OUT/ui-02-extensions.xml" | sed 's/text="//;s/"$//' | grep -v '^$' \
    > "$OUT/extensions-strings.txt" || true
else
  warn "could not reach chrome://extensions through the menu"
fi

# leave chrome://extensions and open a real page before testing the side panel
open_url "https://example.com/"
sleep 6

# 4b) side panel: ensure any previously-open panel is closed, then open it again.
tap_text "关闭" >/dev/null 2>&1 || true
sleep 1

# 4b) side panel: tap the probe extension's action from the extensions menu and
# check whether a panel surface appears (bottom sheet). This is the v0.1 product
# delta; upstream only ships the container behind a flag.
step "side panel probe"
open_extensions_menu || true
tap_text "Lumo" || true
sleep 4
shot "$OUT/screen-03-sidepanel.png"
ui_dump "$OUT/ui-03-sidepanel.xml"
grep -o 'text="[^"]*"' "$OUT/ui-03-sidepanel.xml" 2>/dev/null | sed 's/text="//;s/"$//' | grep -v '^$' \
  > "$OUT/sidepanel-strings.txt" || true

# 4c) CDP snapshot: extension service workers + page targets
step "cdp targets"
D forward tcp:9222 localabstract:chrome_devtools_remote >/dev/null 2>&1 || true
sleep 1
if python3 "$REPO_ROOT/tools/cdp.py" list > "$OUT/cdp-targets.txt" 2>/dev/null; then
  log "captured $(grep -c service_worker "$OUT/cdp-targets.txt") service workers"
else
  warn "CDP not reachable"
fi

# 4d) regression: closing the panel must not kill the browser process
step "close panel regression"
PIDS_BEFORE="$(D shell pidof "$PRODUCT_PKG" | tr -d '\r')"
if tap_text "关闭" || tap_text "Close"; then
  sleep 3
  PIDS_AFTER="$(D shell pidof "$PRODUCT_PKG" | tr -d '\r')"
  if [[ -n "$PIDS_AFTER" ]]; then
    log "browser alive after closing the panel (pid $PIDS_AFTER)"
    echo "close_panel=ok pid=$PIDS_AFTER" > "$OUT/close-panel.txt"
  else
    warn "browser died when closing the side panel"
    echo "close_panel=CRASH (pid before=$PIDS_BEFORE)" > "$OUT/close-panel.txt"
  fi
  shot "$OUT/screen-04-panel-closed.png"
else
  warn "close button not found"
fi

# 5) logcat + probe payload
step "collect logcat"
D logcat -d > "$OUT/logcat.txt" 2>/dev/null || true
D forward tcp:9222 localabstract:chrome_devtools_remote >/dev/null 2>&1 || true
if python3 "$REPO_ROOT/tools/probe-dump.py" --run --out "$OUT/probe.json" 2>/dev/null; then
  python3 - "$OUT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1] + '/probe.json'))
m = d.get('meta', {})
print(f"probe: {m.get('pass')} pass / {m.get('fail')} fail / {m.get('total')} total")
PY
else
  warn "CDP probe dump failed; falling back to logcat parsing"
  python3 - "$OUT" <<'PY'
import json, sys
out = sys.argv[1]
raw = open(f'{out}/logcat.txt', encoding='utf-8', errors='ignore').read()
idx = raw.rfind('PROBE_JSON ')
data = None
if idx >= 0:
    start = raw.index('{', idx)
    depth = 0
    in_str = False
    esc = False
    for i in range(start, len(raw)):
        ch = raw[i]
        if in_str:
            if esc:
                esc = False
            elif ch == '\\':
                esc = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
        elif ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                try:
                    data = json.loads(raw[start:i + 1])
                except json.JSONDecodeError:
                    data = None
                break
if data:
    open(f'{out}/probe.json', 'w').write(json.dumps(data, indent=2))
    m = data.get('meta', {})
    print(f"probe: {m.get('pass')} pass / {m.get('fail')} fail / {m.get('total')} total")
else:
    print('probe: not found in logcat')
PY
fi

# 6) summary
{
  echo "run=$RUN_ID"
  echo "device=$DEVICE_SERIAL pkg=$PRODUCT_PKG"
  echo "apk=$(D shell dumpsys package "$PRODUCT_PKG" | grep -m1 versionName || true)"
  echo "--- extensions visible:"
  grep -iE "lumo|probe|userscript" "$OUT/extensions-strings.txt" 2>/dev/null || echo "(none)"
  echo "--- sw state:"
  grep -iE "Service Worker" "$OUT/extensions-strings.txt" 2>/dev/null || true
  echo "--- close panel:"
  cat "$OUT/close-panel.txt" 2>/dev/null || echo "(not run)"
} | tee "$OUT/summary.txt"

step "gate"
GATE_FAIL=0
if [[ -f "$OUT/probe.json" ]]; then
  PASS="$(python3 -c "import json;print(json.load(open('$OUT/probe.json'))['meta']['pass'])" 2>/dev/null || echo 0)"
  TOTAL="$(python3 -c "import json;print(json.load(open('$OUT/probe.json'))['meta']['total'])" 2>/dev/null || echo 0)"
  log "probe: $PASS/$TOTAL"
  (( PASS * 100 >= TOTAL * 80 )) || { warn "probe pass rate < 80%"; GATE_FAIL=1; }
else
  warn "missing probe.json"; GATE_FAIL=1
fi
for name in Lumo "Lumo MV3 Probe" "Lumo 用户脚本管理器"; do
  grep -q "$name" "$OUT/extensions-strings.txt" 2>/dev/null || { warn "extension not listed: $name"; GATE_FAIL=1; }
done
[[ "$(grep -c 'Service Worker' "$OUT/extensions-strings.txt" 2>/dev/null || echo 0)" -ge 3 ]] \
  || { warn "expected >=3 running service workers"; GATE_FAIL=1; }
grep -q 'close_panel=ok' "$OUT/close-panel.txt" 2>/dev/null \
  || { warn "closing the side panel did not survive"; GATE_FAIL=1; }
if (( GATE_FAIL )); then
  echo "GATE=FAIL" | tee -a "$OUT/summary.txt"
  exit 1
fi
echo "GATE=OK" | tee -a "$OUT/summary.txt"

step "done"
ls -1 "$OUT"
