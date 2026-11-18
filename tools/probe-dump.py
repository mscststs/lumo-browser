#!/usr/bin/env python3
"""Dump the latest MV3 probe result from the running browser via CDP.

Why not logcat: `PROBE_JSON` is >4KB and Android's logcat splits long lines, which
makes a naive regex fail. Reading `chrome.storage.local` from the probe's service
worker is exact and works even when the console line is truncated.

Two practical problems this script solves:

* **MV3 workers idle out.** When the probe SW is gone we load the extension's
  `probe.html` in an existing tab (via `Page.navigate`; `/json/new` returns 500 on
  this build), wait for the worker, then navigate that tab back.
* **The probe measures the *active* tab.** Wake-up navigation leaves an extension
  page in front, where `scripting.executeScript` cannot inject, so we bring an
  http(s) tab to the front before re-running.

Usage: tools/probe-dump.py [--out file.json] [--run] [--keep-tab]

Output shape: {"meta": {...}, "results": [...]} — same shape as the `PROBE_JSON`
console line and what `tools/verify/manifest.json` describes.
"""
import argparse
import asyncio
import json
import sys

sys.path.insert(0, __import__("os").path.dirname(__file__))
from cdp import Session, targets  # noqa: E402

PROBE_NAME = "Lumo MV3 Probe"
PROBE_PAGE = "probe.html"


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


async def probe_extension_id() -> str:
    """Read the probe's extension id from chrome://extensions (developerPrivate)."""
    for t in targets():
        if t.get("type") != "page" or not t.get("url", "").startswith("chrome://extensions"):
            continue
        try:
            async with Session(t["webSocketDebuggerUrl"]) as s:
                r = await s.call("Runtime.evaluate", {
                    "expression": (
                        "(async () => { try { const exts = await chrome.developerPrivate"
                        ".getExtensionsInfo(); const e = exts.find(x => x.name === '"
                        + PROBE_NAME.replace("'", "\\'")
                        + "'); return e ? e.id : ''; } catch (e) { return ''; } })()"
                    ),
                    "awaitPromise": True,
                    "returnByValue": True,
                })
                return r.get("result", {}).get("value") or ""
        except Exception:
            continue
    return ""


# Pages that accept extension injection. The Web Store and chrome:// pages
# reject `scripting.executeScript`, so activating them would poison the run.
BLOCKED_HOSTS = ("chromewebstore.google.com", "chrome.google.com/webstore")
PREFERRED_HOSTS = ("example.com", "example.org", "localhost", "127.0.0.1")


def web_tabs():
    tabs = [t for t in targets()
            if t.get("type") == "page"
            and t.get("url", "").startswith(("http://", "https://"))
            and not any(h in t.get("url", "") for h in BLOCKED_HOSTS)]
    # Prefer a deterministic page (the harness opens example.com) over whatever
    # the user happened to leave in front.
    tabs.sort(key=lambda t: 0 if any(h in t.get("url", "") for h in PREFERRED_HOSTS) else 1)
    return tabs


async def navigate_tab(target, url: str) -> bool:
    try:
        async with Session(target["webSocketDebuggerUrl"]) as s:
            await s.call("Page.enable")
            await s.call("Page.navigate", {"url": url})
        return True
    except Exception:
        return False


async def activate_web_tab() -> bool:
    """Bring an http(s) page to the front so tab-scoped probe items can run."""
    for t in web_tabs():
        try:
            async with Session(t["webSocketDebuggerUrl"]) as s:
                await s.call("Page.bringToFront")
            return True
        except Exception:
            continue
    return False


async def wake_and_find(timeout_s: float = 10.0):
    """Load probe.html in an existing tab, wait for the worker, then restore."""
    ext_id = await probe_extension_id()
    if not ext_id:
        return None
    tab = next(iter(web_tabs()), None)
    if tab is None:
        return None
    original_url = tab.get("url") or "about:blank"
    if not await navigate_tab(tab, f"chrome-extension://{ext_id}/{PROBE_PAGE}"):
        return None

    target = None
    loop = asyncio.get_event_loop()
    deadline = loop.time() + timeout_s
    while loop.time() < deadline:
        target = await find_probe_worker()
        if target:
            break
        await asyncio.sleep(0.5)

    if original_url.startswith(("http://", "https://")):
        await navigate_tab(tab, original_url)
        await asyncio.sleep(1.5)  # let the page commit before tab-scoped probes
    return target


async def main(out, run, keep_tab):
    target = await find_probe_worker()
    if not target:
        print("probe service worker idle; waking it via probe.html", file=sys.stderr)
        target = await wake_and_find()
    if not target:
        print("probe service worker not found", file=sys.stderr)
        return 1

    if not keep_tab and not await activate_web_tab():
        print("no http(s) tab to activate; tab-scoped probes may fail", file=sys.stderr)

    async with Session(target["webSocketDebuggerUrl"]) as s:
        if run:
            await s.call("Runtime.evaluate", {
                "expression": "(async () => { await self.lumoProbe.run(); return 'ran'; })()",
                "awaitPromise": True,
                "returnByValue": True,
            })
        r = await s.call("Runtime.evaluate", {
            "expression": (
                "(async () => await chrome.storage.local.get("
                "['probe:latest', 'probe:meta']))()"
            ),
            "awaitPromise": True,
            "returnByValue": True,
        })
        payload = r.get("result", {}).get("value") or {}

        # The probe stores results (array) and meta (object) under two keys;
        # recompose the record that PROBE_JSON on the console used to be.
        if isinstance(payload, dict) and "probe:latest" in payload:
            payload = {
                "meta": payload.get("probe:meta") or {},
                "results": payload.get("probe:latest") or [],
            }
        if not payload.get("results"):
            print("probe storage empty", file=sys.stderr)
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
    ap.add_argument("--keep-tab", action="store_true", help="do not activate a web tab")
    args = ap.parse_args()
    sys.exit(asyncio.run(main(args.out, args.run, args.keep_tab)))
