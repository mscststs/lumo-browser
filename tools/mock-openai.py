#!/usr/bin/env python3
"""Tiny OpenAI-compatible mock used to prove Lumo's chat pipeline on device.

Endpoints:
  GET  /v1/models              -> {"data":[{"id":"mock-1", ...}]}
  POST /v1/chat/completions    -> SSE stream (or JSON when stream=false)

The reply is deterministic: it echoes the last user message and always contains
the marker `MOCK_OK`, so the harness can assert on rendered text.

Usage: tools/mock-openai.py [--port 8765]
"""
import argparse
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MARKER = "MOCK_OK"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        print("[mock-openai] " + fmt % args, flush=True)

    def _json(self, obj, status=200):
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()

    def do_GET(self):
        if self.path.rstrip("/").endswith("/models"):
            self._json(
                {
                    "object": "list",
                    "data": [
                        {"id": "mock-1", "object": "model", "owned_by": "lumo-test"},
                    ],
                }
            )
            return
        if self.path.rstrip("/") in ("", "/health"):
            self._json({"ok": True})
            return
        self._json({"error": {"message": "not found"}}, 404)

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            req = json.loads(raw or b"{}")
        except json.JSONDecodeError:
            req = {}

        messages = req.get("messages") or []
        last_user = ""
        for m in reversed(messages):
            if m.get("role") == "user":
                content = m.get("content")
                if isinstance(content, str):
                    last_user = content
                elif isinstance(content, list):
                    last_user = " ".join(
                        part.get("text", "") for part in content if isinstance(part, dict)
                    )
                break
        reply = f"{MARKER}: 收到你的消息 —— {last_user.strip()[:120] or '(empty)'}"

        if not req.get("stream"):
            self._json(
                {
                    "id": "chatcmpl-mock",
                    "object": "chat.completion",
                    "created": int(time.time()),
                    "model": req.get("model", "mock-1"),
                    "choices": [
                        {
                            "index": 0,
                            "message": {"role": "assistant", "content": reply},
                            "finish_reason": "stop",
                        }
                    ],
                    "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2},
                }
            )
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()

        def chunk(delta, finish=None):
            payload = {
                "id": "chatcmpl-mock",
                "object": "chat.completion.chunk",
                "created": int(time.time()),
                "model": req.get("model", "mock-1"),
                "choices": [{"index": 0, "delta": delta, "finish_reason": finish}],
            }
            self.wfile.write(f"data: {json.dumps(payload, ensure_ascii=False)}\n\n".encode())
            self.wfile.flush()

        chunk({"role": "assistant", "content": ""})
        # Stream in small pieces so the UI shows a real streaming reply.
        for i in range(0, len(reply), 8):
            chunk({"content": reply[i : i + 8]})
            time.sleep(0.02)
        chunk({}, "stop")
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8765)
    args = ap.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"[mock-openai] listening on 127.0.0.1:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
