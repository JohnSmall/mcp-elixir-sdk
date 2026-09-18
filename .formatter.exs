[
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs}",
    # MES-51 scoped gate 1 to conformance/lib/ ONLY. MES-88 widens it to the whole of
    # conformance/. The MES-51 reason for the narrow scope was that the pre-existing
    # adapters at the conformance/ root do not pass gate 2 — but gate 1 has NO compile
    # dependency, so it never had to share gate 2's scope. Measured at 7e935c2: two
    # committed files were unformatted while gate 1 correctly returned rc=0
    # (controls/etcc_attribution_controls.exs, controls/exunit_rows_controls.exs); both
    # are formatted by this ticket. elixirc_paths (gate 2/4) and .credo.exs (gate 3)
    # stay as MES-51 left them — PM ruling, MES-88 `26994`.
    # NOTE FOR THE MERGE GATE: this widens gate 1's reach for EVERY ticket, not just
    # this one. A conformance/ script is now gate-1 material wherever it sits.
    "conformance/**/*.{ex,exs}",
    ".credo.exs"
  ]
]
