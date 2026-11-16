#!/usr/bin/env python3
"""Dump the latest MV3 probe result from the running browser via CDP.

Why not logcat: `PROBE_JSON` is >4KB and Android's logcat splits long lines,
which makes a naive regex fail. Reading `chrome.storage.local` from the probe's
service worker is exact and works even when the console line is truncated.

Usage: tools/probe-dump.py [--out file.json]
"""
import argparse
import asyncio
import json
import sys

sys.path.insert(0, __import__("os").path.dirname(__file__))
from cdp import Session, targets  # noqa: E402

PROBE_NAME = "Lumo MV3 Probe"


async def find_probe_worker():
    for t in targets():
        if t.get("type") != "service_worker":
            continue
        try:
            async with Session(t["webSocketDebuggerUrl"]) as s:
                r = await s.call(
                    "Runtime.evaluate",
                    {"expression": "chrome.runtime.getManifest().name", "returnByValue": True},
                )
                if r.get("result", {}).get("value") == PROBE_NAME:
                    return t
        except Exception:
            continue
    return None


async def main(out, run):
    target = await find_probe_worker()
    if not target:
        print("probe service worker not found", file=sys.stderr)
        return 1
    async with Session(target["webSocketDebuggerUrl"]) as s:
        if run:
            await s.call(
                "Runtime.evaluate",
                {
                    "expression": "(async () => { await self.lumoProbe.run(); return 'ran'; })()",
                    "awaitPromise": True,
                    "returnByValue": True,
                },
            )
        r = await s.call(
            "Runtime.evaluate",
            {
                "expression": "(async () => await chrome.storage.local.get('probe:latest'))()",
                "awaitPromise": True,
                "returnByValue": True,
            },
        )
        payload = r.get("result", {}).get("value")
        if not payload:
            print("probe:latest empty", file=sys.stderr)
            return 1
        text = json.dumps(payload, ensure_ascii=False, indent=2)
        if out:
            open(out, "w").write(text)
        else:
            print(text)
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out")
    ap.add_argument("--run", action="store_true", help="trigger a fresh probe run first")
    args = ap.parse_args()
    sys.exit(asyncio.run(main(args.out, args.run)))
