#!/usr/bin/env bash
# End-to-end Lumo (AI sidebar extension) test against a local OpenAI-compatible
# mock. Proves: side panel renders, provider config loads, chat request streams,
# and the reply is rendered — all inside Lumo Browser on a real device.
#
#   scripts/verify/lumo-e2e.sh [--port 8765]
#
# Requirements: adb device, `--remote-debugging-port=9222` in the browser command
# line (verify.sh sets it), python3 `websockets`, and `tools/mock-openai.py`.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
need_device

PORT="${1:-8765}"
PORT="${PORT#--port=}"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
OUT="$REPO_ROOT/artifacts/verify/lumo-e2e-$RUN_ID"
mkdir -p "$OUT"

step "mock provider"
if ! curl -sf "http://127.0.0.1:$PORT/health" >/dev/null; then
  setsid nohup python3 "$REPO_ROOT/tools/mock-openai.py" --port "$PORT" \
    > "$OUT/mock.log" 2>&1 < /dev/null &
  sleep 2
fi
curl -sf "http://127.0.0.1:$PORT/health" >/dev/null || die "mock provider not reachable on :$PORT"

step "adb wiring"
D reverse "tcp:$PORT" "tcp:$PORT" >/dev/null
D reverse tcp:9222 tcp:9222 >/dev/null
log "adb reverse: $(D reverse --list | tr '\n' ' ')"

step "open Lumo side panel"
D shell su -c "am force-stop $PRODUCT_PKG" || true
D logcat -c || true
D shell su -c "am start -a android.intent.action.VIEW -d 'https://example.com/' -n $PRODUCT_PKG/${MAIN_ACTIVITY:-com.google.android.apps.chrome.Main}" >/dev/null
sleep 8
open_extensions_menu || true
sleep 2
tap_text "Lumo" || die "cannot open Lumo from the extensions menu"
sleep 6

step "configure provider via CDP"
python3 - "$PORT" "$OUT" <<'PY'
import asyncio, json, sys
sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.dirname(__file__)))
from tools.cdp import targets, Session, pick

port, out = sys.argv[1], sys.argv[2]

async def main():
    t = pick(targets(), 'sidepanel.html')
    if not t:
        print('no sidepanel target', file=sys.stderr)
        return 1
    providers = [{
        "id": "mock", "name": "Mock", "type": "openai-chat",
        "baseUrl": f"http://127.0.0.1:{port}/v1", "apiKey": "sk-mock",
        "models": [{
            "id": "mock-1", "modelId": "mock-1", "displayName": "Mock One",
            "isVision": False, "contextWindow": 32000,
        }],
    }]
    async with Session(t['webSocketDebuggerUrl']) as s:
        expr = ("(async () => { await chrome.storage.local.set("
                + json.dumps({"providers": providers,
                              "selectedModel": {"providerId": "mock", "modelId": "mock-1"}})
                + "); return 'ok'; })()")
        res = await s.call('Runtime.evaluate', {'expression': expr, 'awaitPromise': True, 'returnByValue': True})
        print('storage:', res.get('result', {}).get('value'))
        await s.call('Page.reload', {'ignoreCache': False})
        await asyncio.sleep(5)
        res = await s.call('Runtime.evaluate', {'expression': 'document.body.innerText.slice(0,300)', 'returnByValue': True})
        open(f"{out}/panel-before-send.txt", "w").write(res.get('result', {}).get('value') or '')
        return 0

sys.exit(asyncio.run(main()))
PY

step "send a message"
python3 - "$OUT" <<'PY'
import asyncio, sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from tools.cdp import targets, Session, pick

out = sys.argv[1]
text = "你好，验证 Lumo 在 Lumo Browser 中的完整链路"

async def main():
    t = pick(targets(), 'sidepanel.html')
    if not t:
        print('no sidepanel target', file=sys.stderr)
        return 1
    async with Session(t['webSocketDebuggerUrl']) as s:
        await s.call('Runtime.evaluate', {'expression': "document.querySelector('textarea')?.focus()", 'userGesture': True, 'returnByValue': True})
        await s.call('Input.insertText', {'text': text})
        for kind in ('keyDown', 'keyUp'):
            await s.call('Input.dispatchKeyEvent', {'type': kind, 'windowsVirtualKeyCode': 13,
                                                   'nativeVirtualKeyCode': 13, 'key': 'Enter',
                                                   'code': 'Enter', 'text': '\r'})
        for _ in range(20):
            await asyncio.sleep(1)
            res = await s.call('Runtime.evaluate', {'expression': 'document.body.innerText', 'returnByValue': True})
            body = res.get('result', {}).get('value') or ''
            if 'MOCK_OK' in body:
                open(f"{out}/panel-after-send.txt", "w").write(body)
                print('reply rendered (MOCK_OK found)')
                return 0
        open(f"{out}/panel-after-send.txt", "w").write(body)
        print('reply not observed', file=sys.stderr)
        return 1

sys.exit(asyncio.run(main()))
PY

step "evidence"
shot "$OUT/screen-lumo-e2e.png"
D logcat -d > "$OUT/logcat.txt" 2>/dev/null || true
grep -c "MOCK_OK" "$OUT/panel-after-send.txt" 2>/dev/null | sed 's/^/MOCK_OK occurrences: /' | tee "$OUT/summary.txt"
log "done: $OUT"
