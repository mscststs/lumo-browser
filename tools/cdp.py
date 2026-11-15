#!/usr/bin/env python3
"""Minimal Chrome DevTools Protocol client for the Lumo Browser test harness.

Usage:
    tools/cdp.py list
    tools/cdp.py eval --target <url-substring> --expr '...' [--await] [--user-gesture]
    tools/cdp.py type --target <url-substring> --selector 'textarea' --text 'hi' --enter

Requires: `websockets` (python). The browser must run with
`--remote-debugging-port=9222` and `adb forward tcp:9222 localabstract:chrome_devtools_remote`.
"""
import argparse
import asyncio
import json
import sys
import urllib.request

import websockets


def http_json(path):
    with urllib.request.urlopen(f"http://127.0.0.1:9222{path}", timeout=10) as r:
        return json.loads(r.read())


def targets():
    return http_json("/json/list")


def pick(target_list, needle):
    for t in target_list:
        url = t.get("url", "")
        title = t.get("title", "")
        if needle in url or needle in title:
            return t
    return None


class Session:
    def __init__(self, ws_url):
        self.ws_url = ws_url
        self._id = 0

    async def __aenter__(self):
        self.ws = await websockets.connect(self.ws_url, max_size=16 * 1024 * 1024)
        return self

    async def __aexit__(self, *exc):
        await self.ws.close()

    async def call(self, method, params=None):
        self._id += 1
        msg_id = self._id
        await self.ws.send(json.dumps({"id": msg_id, "method": method, "params": params or {}}))
        while True:
            raw = await asyncio.wait_for(self.ws.recv(), timeout=60)
            data = json.loads(raw)
            if data.get("id") == msg_id:
                if "error" in data:
                    raise RuntimeError(f"{method}: {data['error']}")
                return data.get("result", {})


async def cmd_list(_args):
    for t in targets():
        print(f"{t.get('type'):14} {t.get('title')[:48]:48} {t.get('url')[:90]}")
    return 0


async def _eval(target, expr, await_promise, user_gesture):
    async with Session(target["webSocketDebuggerUrl"]) as s:
        res = await s.call(
            "Runtime.evaluate",
            {
                "expression": expr,
                "awaitPromise": await_promise,
                "userGesture": user_gesture,
                "returnByValue": True,
            },
        )
    if "exceptionDetails" in res:
        print(json.dumps(res["exceptionDetails"], ensure_ascii=False), file=sys.stderr)
        return 1
    value = res.get("result", {}).get("value")
    print(json.dumps(value, ensure_ascii=False) if not isinstance(value, str) else value)
    return 0


async def cmd_eval(args):
    ts = targets()
    target = pick(ts, args.target)
    if not target:
        print(f"no target matching {args.target!r}", file=sys.stderr)
        return 1
    return await _eval(target, args.expr, args.await_promise, args.user_gesture)


async def cmd_type(args):
    ts = targets()
    target = pick(ts, args.target)
    if not target:
        print(f"no target matching {args.target!r}", file=sys.stderr)
        return 1
    async with Session(target["webSocketDebuggerUrl"]) as s:
        await s.call(
            "Runtime.evaluate",
            {
                "expression": (
                    f"(() => {{ const el = document.querySelector({json.dumps(args.selector)});"
                    " if (!el) return false; el.focus(); return true; })()"
                ),
                "returnByValue": True,
                "userGesture": True,
            },
        )
        await s.call("Input.insertText", {"text": args.text})
        if args.enter:
            for kind in ("keyDown", "keyUp"):
                await s.call(
                    "Input.dispatchKeyEvent",
                    {
                        "type": kind,
                        "windowsVirtualKeyCode": 13,
                        "nativeVirtualKeyCode": 13,
                        "key": "Enter",
                        "code": "Enter",
                        "text": "\r",
                    },
                )
    return 0


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list")

    e = sub.add_parser("eval")
    e.add_argument("--target", required=True)
    e.add_argument("--expr", required=True)
    e.add_argument("--await", dest="await_promise", action="store_true")
    e.add_argument("--user-gesture", action="store_true")

    t = sub.add_parser("type")
    t.add_argument("--target", required=True)
    t.add_argument("--selector", default="textarea")
    t.add_argument("--text", required=True)
    t.add_argument("--enter", action="store_true")

    args = p.parse_args()
    handler = {"list": cmd_list, "eval": cmd_eval, "type": cmd_type}[args.cmd]
    sys.exit(asyncio.run(handler(args)))


if __name__ == "__main__":
    main()
