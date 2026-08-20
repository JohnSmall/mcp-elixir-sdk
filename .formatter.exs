[
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs}",
    # MES-51. Gate 1 was blind to conformance/ (MES-46, measured). Scoped to
    # conformance/lib/ ONLY — the pre-existing adapters alongside it do not pass
    # gate 2, and dragging them in would be another ticket's work smuggled in here.
    "conformance/lib/**/*.{ex,exs}",
    ".credo.exs"
  ]
]
