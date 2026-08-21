#!/usr/bin/env python3
"""Null-implementation control #3 for the conformance CLIENT leg: one request, then stop.

The STRICTEST of three, and the one that scores LOWEST. It POSTs a single
well-formed JSON-RPC 2.0 request for a method that does not exist
(`conformance/null-control`), reads nothing into any model of the protocol, and
exits 0. It implements no MCP behaviour whatsoever.

## Why the strictest null scores lowest, which is the point of running all three

Sprint 4: 2/32, 2/32, **1/32** across the three. The mechanism, worth carrying
into any reading of a client sheet: for a do-nothing client
`http-standard-headers` is a PASS assembled from **eleven SKIPPED checks and not
one that could fail**. Send anything at all and a twelfth check appears — and
fails. So "doing more" costs a pass, and a pass can be assembled entirely out of
absence.

That is why MES-57 reports the inversion instead of picking a null: with one
control the client figure would rest on which null someone chose, and the
flattering choice is the do-nothing one.

The three nulls, and why a control is written in Python rather than Elixir, are
stated once in `null_client_exit0.py`.

The beacon is four lines of stdlib and imports no SDK, so
`beacon.adapter_sources` names THIS file and a control cannot be reported as a
measurement.
"""

import datetime
import json
import os
import sys
import urllib.error
import urllib.request

SOURCE = "conformance/controls/null_client_request.py"


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


def post_one_request(url):
    """POST one well-formed JSON-RPC request for a nonexistent method. Never raises."""
    body = json.dumps(
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "conformance/null-control",
            "params": {},
        }
    ).encode()

    request = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "content-type": "application/json",
            "accept": "application/json, text/event-stream",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            response.read()
    except (urllib.error.URLError, OSError, ValueError):
        # Deliberately swallowed, and exiting 0 regardless. The harness's
        # reducer fails a scenario on a non-zero exit INDEPENDENTLY of every
        # check, so a non-zero exit here would replace the measurement with a
        # note about this file. Same discipline as the measurement adapter's.
        pass


if __name__ == "__main__":
    beacon()
    if len(sys.argv) > 1:
        post_one_request(sys.argv[-1])
    sys.exit(0)
