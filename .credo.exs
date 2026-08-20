# MES-51. The only reason this file exists.
#
# Gate 3 (`mix credo`) was blind to conformance/ and — unlike gates 1, 2 and 4 —
# could NOT be fixed from mix.exs. Mechanism, measured on main @ ae0e922: with no
# .credo.exs present, credo loads its bundled default config, whose `files.included`
# is the HARDCODED list restated below. Credo never reads `elixirc_paths`, so the
# mix.exs change that brings gates 2 and 4 onto conformance/lib/ does not drag credo
# along with it. `mix credo --debug` reported "Checking 121 source files"; the files
# under conformance/ were not among them.
#
# This is a MERGE-ONLY config. It restates credo's default `files.included` verbatim
# and appends exactly one entry. `checks:` is deliberately ABSENT so the enabled-check
# set keeps tracking credo's default rather than being frozen at whatever it was on
# the day this file was written (verified: 57 enabled checks before and after).
[
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "lib/**/*.{ex,exs}",
          "src/",
          "test/**/*.{ex,exs}",
          "web/",
          "apps/*/lib/",
          "apps/*/src/",
          "apps/*/test/",
          "apps/*/web/",
          # The one addition: MES-51's run-provenance tooling.
          "conformance/lib/**/*.{ex,exs}"
        ],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      }
    }
  ]
]
