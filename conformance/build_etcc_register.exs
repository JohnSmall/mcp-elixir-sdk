# Builds docs/conformance/etcc-register.json from the authored decisions file and
# MES-83's ExUnit row artefact.
#
#     mix run conformance/build_etcc_register.exs
#
# The spec-file md5s below are the PM's condition on materialising the pinned
# spec tree (MES-81 comment 26027): the md5 of every file an anchor cites goes
# into the DELIVERABLE, not just into a close-out, so an anchor stays verifiable
# by anyone who re-fetches the spec at 5f5440bb — `/tmp` is ephemeral and this
# project has already been bitten by evidence that lived only in a run tree.
#
# Recomputed, not transcribed: `mix run conformance/controls/etcc_register_controls.exs spec`
# re-md5s a materialised tree and diffs it against this list.

spec_md5s = %{
  "schema/2026-07-28/schema.ts" => "48a009165e07f6732e38baf91291de87",
  "docs/specification/2026-07-28/basic/index.mdx" => "1b680a56e96533ff28f6eac07bd51bdc",
  "docs/specification/2026-07-28/basic/patterns/subscriptions.mdx" =>
    "f01270882fe8e2d0c2632c19ab8242ba",
  "docs/specification/2026-07-28/basic/transports/stdio.mdx" =>
    "b50a3e1ca27476c1da2b920a10e4b076",
  "docs/specification/2026-07-28/basic/transports/streamable-http.mdx" =>
    "63f792fddd2a9d81026ebafe6930ff87",
  "docs/specification/2026-07-28/basic/versioning.mdx" => "6b2476585e9e10e1b4c3706a832f5fb5",
  "docs/specification/2026-07-28/changelog.mdx" => "5ced9bc596491383397e0637242b746e",
  "docs/specification/2026-07-28/server/tools.mdx" => "c302125aae381e9be1feb96305341d4b"
}

path = MCP.Conformance.ETCCRegister.write(spec_md5s: spec_md5s)
register = path |> File.read!() |> Jason.decode!()

IO.puts("[etcc-register] wrote #{path}")
IO.puts("  in scope      #{register["totals"]["in_scope"]}")

for {label, n} <- Enum.sort(register["totals"]["by_label"]) do
  IO.puts("  #{String.pad_trailing(label, 13)} #{n}")
end

IO.puts("  out of scope  #{register["totals"]["out_of_scope"]}")
IO.puts("  escalated     #{register["totals"]["escalated"]}")
