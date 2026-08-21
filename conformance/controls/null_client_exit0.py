#!/usr/bin/env python3
"""Null-implementation control #1 for the conformance CLIENT leg: exit 0.

The weakest of three. It opens no socket, sends no byte and reads no argv
beyond what the beacon needs. Every check that the harness scores against it is
scored against a client that did nothing at all.

## Three nulls, because on this leg "the null control" is not one number

Sprint 4 measured three nulls of increasing strictness and got 2/32, 2/32 and
**1/32**: a STRICTER null scores LOWER. That is not a rounding artefact, it is
the mechanism the client sheet has to be read through. For a do-nothing client,
`http-standard-headers` is a PASS assembled from eleven SKIPPED checks and not
one check that could fail; send a single well-formed request and a twelfth check
appears and fails. So a control that "does more" earns less, and quoting one
null as "the" control would let whoever picked it pick the answer.

MES-57 therefore runs all three and reports the inversion rather than a
flattering one.

## Why this is Python, and why that is not a gap to be closed

Inherited verbatim from `null_server.py`, and it is the same guarantee: writing
a control in Elixir would put it inside the umbrella project whose absence it
exists to simulate — one `mix run`, one `Code.require_file`, one transitively
loaded application, and the control is quietly exercising the thing it is
supposed to prove nothing about. Its job is to contain no SDK, and the cheapest
way to guarantee that is for it to be unable to reach one.

That puts this file outside all six DoD gates. That is the PRICE of the
control's independence and it is a good price.

## The beacon

Four lines of stdlib, appending one JSON line to the file the runner names, so
the run satisfies ADAPTER_NEVER_STARTED and so `beacon.adapter_sources` names
THIS file. That is how `MCP.Conformance.Census` tells a control run from a
measurement run without taking the manifest's word for it. No SDK is imported
to do it.
"""

import datetime
import json
import os
import sys

SOURCE = "conformance/controls/null_client_exit0.py"


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


if __name__ == "__main__":
    beacon()
    sys.exit(0)
