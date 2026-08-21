#!/usr/bin/env python3
"""Null-implementation control for the conformance server leg.

Answers JSON-RPC -32601 to EVERY method, over HTTP 200. It implements no MCP
behaviour whatsoever. Any scored scenario it passes is a scenario whose checks
cannot distinguish this SDK from its absence, and the headline is not meaningful
without that number: MES-49 measured 6 of 37 for a server like this one, and
reading every fixture beforehand predicted only 3 of those 6.

## Why this is Python, and why that is not a gap to be closed

This file is outside all six DoD gates. That is the PRICE of the control's
independence and it is a good price. Writing it in Elixir would put it inside
the umbrella project whose absence it exists to simulate — one `mix run`, one
`Code.require_file`, one transitively-loaded application, and the control is
quietly exercising the thing it is supposed to prove nothing about. Its job is
to contain no SDK, and the cheapest way to guarantee that is for it to be
unable to reach one.

If a later reader is tempted to "fix" the coverage gap: don't. Delete this
comment only when you have found a way to keep the guarantee.

## The beacon

Four lines of stdlib, appending one JSON line to the file the runner names, so
the run satisfies ADAPTER_NEVER_STARTED and so `beacon.adapter_sources` names
THIS file. That is how a reader — and `MCP.Conformance.Census` — tells a control
run from a measurement run without taking the manifest's word for it. No SDK is
imported to do it.
"""

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


def beacon():
    """Append one adapter beacon line, or do nothing. Never raises."""
    path, token = (
        os.environ.get("MCP_CONFORMANCE_BEACON"),
        os.environ.get("MCP_CONFORMANCE_BEACON_TOKEN"),
    )
    if not path or not token:
        return
    try:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(
                json.dumps(
                    {
                        "token": token,
                        "role": "adapter",
                        "source": "conformance/controls/null_server.py",
                        "os_pid": str(os.getpid()),
                        "at": __import__("datetime")
                        .datetime.now(__import__("datetime").timezone.utc)
                        .isoformat()
                        .replace("+00:00", "Z"),
                    }
                )
                + "\n"
            )
    except OSError:
        pass


class NullHandler(BaseHTTPRequestHandler):
    def do_POST(self):  # noqa: N802 — BaseHTTPRequestHandler's naming, not ours
        length = int(self.headers.get("content-length") or 0)
        try:
            request = json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            request = {}

        body = json.dumps(
            {
                "jsonrpc": "2.0",
                "id": request.get("id"),
                "error": {"code": -32601, "message": "Method not found"},
            }
        ).encode()

        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        """Silent: the harness's transcript is the measurement, not our noise."""


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 3002
    beacon()
    HTTPServer(("127.0.0.1", port), NullHandler).serve_forever()
