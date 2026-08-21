#!/usr/bin/env python3
"""Null-implementation control #2 for the conformance CLIENT leg: connect, say nothing.

The middle strictness of three. It opens a TCP connection to the server URL the
harness appends as the last argv, sends **no byte**, closes, and exits 0. It
speaks no HTTP and no JSON-RPC.

Its job is to separate two things a single null cannot: a client that never
reached the server at all (`null_client_exit0.py`) from one that reached it and
said nothing. Sprint 4 measured both at 2/32 — the harness's mock server learns
nothing from a bare TCP open — and that equality is itself the finding, because
it locates where the third null's LOWER score comes from: not from connecting,
but from sending.

The three nulls, the inversion they demonstrate, and why a control is written in
Python rather than Elixir are stated once, in `null_client_exit0.py`. Read that
file first; this one is the same control with one more thing done.

The beacon is four lines of stdlib and imports no SDK, so
`beacon.adapter_sources` names THIS file and a control cannot be reported as a
measurement.
"""

import datetime
import json
import os
import socket
import sys
from urllib.parse import urlparse

SOURCE = "conformance/controls/null_client_connect.py"


def beacon(source=SOURCE):
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
                        "source": source,
                        "os_pid": str(os.getpid()),
                        "at": datetime.datetime.now(datetime.timezone.utc)
                        .isoformat()
                        .replace("+00:00", "Z"),
                    }
                )
                + "\n"
            )
    except OSError:
        pass


def connect_and_say_nothing(url):
    """Open a TCP connection, send nothing, close. Never raises."""
    try:
        parsed = urlparse(url)
        host = parsed.hostname or "127.0.0.1"
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
        with socket.create_connection((host, port), timeout=5):
            pass
    except (OSError, ValueError):
        # Exiting non-zero would fail the scenario on the harness's exit-code
        # disjunct INSTEAD of on its checks, which would hide what the checks
        # said — and what the checks say is the entire measurement. Same
        # discipline as the measurement adapter's.
        pass


if __name__ == "__main__":
    beacon()
    if len(sys.argv) > 1:
        connect_and_say_nothing(sys.argv[-1])
    sys.exit(0)
