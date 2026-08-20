defmodule MCP.Conformance.ServerHandler do
  @moduledoc """
  `MCP.Server.Handler` implementation driven by the MCP conformance harness in
  **server mode** at protocol revision **2026-07-28**.

  Run it via `conformance/server_adapter.exs`; measured against
  `@modelcontextprotocol/conformance@0.2.0-alpha.11`.

  ## The rule this file follows, stated so a later reader can check it

  **Nothing here exists to make a scenario green that our SDK would otherwise
  fail.** Every tool below implements a behaviour the harness's own
  *"Server Implementation Requirements"* section names, and does so the way a
  consumer of this SDK would have to write it. Where the SDK cannot express the
  required behaviour, this file implements the **closest thing the SDK's public
  contract allows** and the gap is escalated (A1) rather than routed around —
  see the `## Known SDK gaps exercised by this fixture` section. A scenario that
  fails because the SDK cannot do the thing is the measurement working.

  Corollary, and the reason it is worth writing down: this is not a mock. It is
  an *implementation of this SDK's handler behaviour*, so friction here is
  evidence about `MCP.Server.Handler`, not merely about the fixture.

  ## Stateless, and what that forces

  In the 2026-07-28 core (SEP-2575) the dispatch is per-request and the handler
  `state` returned from a callback does **not** persist across requests. Two
  things in this fixture genuinely need to outlive a request — the MRTR signing
  key, and the mutable tool/prompt lists the `server-stateless` diagnostic hooks
  toggle — so they live in a launch-owned ETS table (`ensure_store/0`), not in
  `state`. That is the same thing a real stateless deployment would have to do,
  one storage tier down.

  MRTR continuations do **not** live there: they ride entirely inside the
  signed `requestState` token (`MCP.Conformance.RequestState`), which is what
  makes any instance able to service the retry.

  ## Known SDK gaps exercised by this fixture

    * `prompts/get` is not wired for MRTR — `MCP.Server.Dispatch` sets
      `ctx.input` only on `tools/call`, and its `prompts/get` shape function
      has no `{:input_required, …}` clause. `test_input_required_result_prompt`
      below therefore returns the input-required *body* through the ordinary
      `{:ok, result, state}` path, where `Dispatch` overwrites `resultType`
      with `"complete"`. That is the gap made visible on the wire rather than
      hidden behind a crash.
    * `MCP.Protocol.Messages.MRTR.continuation_from_params/1` returns `nil`
      unless `requestState` is present, so a retry carrying `inputResponses`
      **and no `requestState`** is invisible to the handler. Every MRTR tool
      here therefore mints a `requestState` on round 1 — not as a trick, but
      because it is the only continuation channel the SDK offers.
    * A handler error return is `{:error, code, message, state}` with **no
      `data` slot**, so `test_missing_capability` cannot attach the
      `error.data.requiredCapabilities` object that `-32021` requires.
    * `MRTR.input_required/2` is spec'd `list() | nil` while the wire type
      `InputRequests` is a JSON **object** keyed by input name. This file sends
      a map, per the schema.
  """

  @behaviour MCP.Server.Handler

  alias MCP.Conformance.RequestState
  alias MCP.Protocol.Meta
  alias MCP.Server.ToolContext

  @store :mcp_conformance_server_store

  @test_image_base64 "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="
  @test_audio_base64 "UklGRiYAAABXQVZFZm10IBAAAAABAAEAQB8AAAB9AAACABAAZGF0YQIAAAA="

  @no_args %{"type" => "object", "properties" => %{}}

  # ---------------------------------------------------------------------------
  # Launch-owned store
  # ---------------------------------------------------------------------------

  @doc """
  Creates the launch-owned ETS table if it does not exist, and returns its name.

  Idempotent, and called from both `init/1` and the adapter script: the adapter
  calls it first so the table is owned by the long-lived script process rather
  than by whichever process happens to build the plug config.
  """
  @spec ensure_store() :: atom()
  def ensure_store do
    case :ets.whereis(@store) do
      :undefined ->
        :ets.new(@store, [:named_table, :public, :set])
        :ets.insert(@store, {:signing_key, RequestState.new_key()})
        @store

      _ref ->
        @store
    end
  end

  defp store_get(key, default) do
    case :ets.lookup(ensure_store(), key) do
      [{^key, value}] -> value
      [] -> default
    end
  end

  defp store_put(key, value), do: :ets.insert(ensure_store(), {key, value})

  defp signing_key, do: store_get(:signing_key, <<>>)

  # Every open `subscriptions/listen` sink, keyed by subscription id.
  defp stream_sinks do
    ensure_store()
    |> :ets.match_object({{:stream, :_}, :_})
    |> Enum.map(fn {{:stream, _id}, sink} -> sink end)
  end

  defp broadcast(method, params) do
    Enum.each(stream_sinks(), fn sink ->
      ToolContext.stream(%ToolContext{stream_sink: sink}, method, params)
    end)
  end

  @impl true
  def init(_opts) do
    ensure_store()
    {:ok, %{}}
  end

  # ---------------------------------------------------------------------------
  # Tools — listing
  # ---------------------------------------------------------------------------

  @impl true
  def handle_list_tools(_cursor, _ctx, state) do
    {:ok, content_tools() ++ mrtr_tools() ++ diagnostic_tools() ++ dynamic_tools(), nil, state}
  end

  defp tool(name, description, schema \\ @no_args) do
    %{"name" => name, "description" => description, "inputSchema" => schema}
  end

  defp content_tools do
    [
      tool("test_simple_text", "Tests simple text content response"),
      tool("test_image_content", "Tests image content response"),
      tool("test_audio_content", "Tests audio content response"),
      tool("test_multiple_content_types", "Tests multiple content types in response"),
      tool("test_embedded_resource", "Tests embedded resource content"),
      tool("test_tool_with_logging", "Tests tool that emits log messages"),
      tool("test_tool_with_progress", "Tests tool with progress notifications"),
      tool("test_error_handling", "Tests error handling")
    ]
  end

  defp mrtr_tools do
    [
      tool(
        "test_input_required_result_elicitation",
        "SEP-2322 MRTR: requests one elicitation input, then completes"
      ),
      tool(
        "test_input_required_result_sampling",
        "SEP-2322 MRTR: requests one sampling input, then completes"
      ),
      tool(
        "test_input_required_result_list_roots",
        "SEP-2322 MRTR: requests the client's roots, then completes"
      ),
      tool(
        "test_input_required_result_request_state",
        "SEP-2322 MRTR: round-trips an integrity-protected requestState"
      ),
      tool(
        "test_input_required_result_multiple_inputs",
        "SEP-2322 MRTR: requests elicitation, sampling and roots together"
      ),
      tool(
        "test_input_required_result_multi_round",
        "SEP-2322 MRTR: two input rounds with an evolving requestState"
      ),
      tool(
        "test_input_required_result_tampered_state",
        "SEP-2322 MRTR: rejects a requestState that fails integrity verification"
      ),
      tool(
        "test_input_required_result_capabilities",
        "SEP-2322 MRTR: only requests input methods the client declared"
      )
    ]
  end

  defp diagnostic_tools do
    [
      tool(
        "test_missing_capability",
        "SEP-2575 diagnostic: requires the sampling client capability"
      ),
      tool(
        "test_streaming_elicitation",
        "SEP-2575 diagnostic: response stream carries results, never independent requests"
      ),
      tool(
        "test_logging_tool",
        "SEP-2575 diagnostic: logs only when _meta carries io.modelcontextprotocol/logLevel"
      ),
      tool("test_trigger_tool_change", "SEP-2575 diagnostic: mutates the tool list"),
      tool("test_trigger_prompt_change", "SEP-2575 diagnostic: mutates the prompt list"),
      tool(
        "json_schema_2020_12_tool",
        "Tool with JSON Schema 2020-12 features",
        json_schema_2020_12()
      ),
      tool(
        "test_custom_header_tool",
        "SEP-2243 diagnostic: a tool with an x-mcp-header annotated parameter",
        %{
          "type" => "object",
          "properties" => %{
            "greeting" => %{"type" => "string", "x-mcp-header" => "Greeting"}
          },
          "required" => ["greeting"]
        }
      )
    ]
  end

  # Verbatim from the `json-schema-2020-12` scenario's own "Server Implementation
  # Requirements". Not scored at 2026-07-28 (`not_scored / reason: pending`), so
  # it can move no figure — it is here because the scenario is the only thing
  # that exercises MES-17's server-side preservation, and a scenario that reports
  # "tool not found" measures the fixture rather than the SDK.
  defp json_schema_2020_12 do
    %{
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "type" => "object",
      "$defs" => %{
        "address" => %{
          "$anchor" => "addressDef",
          "type" => "object",
          "properties" => %{"street" => %{"type" => "string"}, "city" => %{"type" => "string"}}
        }
      },
      "properties" => %{
        "name" => %{"type" => "string"},
        "address" => %{"$ref" => "#/$defs/address"},
        "contactMethod" => %{"type" => "string", "enum" => ["phone", "email"]},
        "phone" => %{"type" => "string"},
        "email" => %{"type" => "string"}
      },
      "allOf" => [%{"anyOf" => [%{"required" => ["phone"]}, %{"required" => ["email"]}]}],
      "if" => %{
        "properties" => %{"contactMethod" => %{"const" => "phone"}},
        "required" => ["contactMethod"]
      },
      "then" => %{"required" => ["phone"]},
      "else" => %{"required" => ["email"]},
      "additionalProperties" => false
    }
  end

  # The list-changed diagnostics must actually change the list they notify
  # about, or the notification is a claim about nothing.
  defp dynamic_tools do
    if store_get(:tools_bumped, false) do
      [tool("test_dynamic_tool", "Added by test_trigger_tool_change")]
    else
      []
    end
  end

  # ---------------------------------------------------------------------------
  # Tools — content scenarios
  # ---------------------------------------------------------------------------

  @impl true
  def handle_call_tool("test_simple_text", _args, _ctx, state) do
    {:ok, [text("This is a simple text response for testing.")], state}
  end

  def handle_call_tool("test_image_content", _args, _ctx, state) do
    {:ok, [%{"type" => "image", "data" => @test_image_base64, "mimeType" => "image/png"}], state}
  end

  def handle_call_tool("test_audio_content", _args, _ctx, state) do
    {:ok, [%{"type" => "audio", "data" => @test_audio_base64, "mimeType" => "audio/wav"}], state}
  end

  def handle_call_tool("test_multiple_content_types", _args, _ctx, state) do
    content = [
      text("Multiple content types test:"),
      %{"type" => "image", "data" => @test_image_base64, "mimeType" => "image/png"},
      %{
        "type" => "resource",
        "resource" => %{
          "uri" => "test://mixed-content-resource",
          "mimeType" => "application/json",
          "text" => Jason.encode!(%{"test" => "data", "value" => 123})
        }
      }
    ]

    {:ok, content, state}
  end

  def handle_call_tool("test_embedded_resource", _args, _ctx, state) do
    content = [
      %{
        "type" => "resource",
        "resource" => %{
          "uri" => "test://embedded-resource",
          "mimeType" => "text/plain",
          "text" => "This is an embedded resource content."
        }
      }
    ]

    {:ok, content, state}
  end

  def handle_call_tool("test_tool_with_logging", _args, ctx, state) do
    ToolContext.log(ctx, "info", "Tool execution started")
    ToolContext.log(ctx, "info", "Tool processing data")
    ToolContext.log(ctx, "info", "Tool execution completed")
    {:ok, [text("Tool with logging executed successfully")], state}
  end

  def handle_call_tool("test_tool_with_progress", _args, ctx, state) do
    ToolContext.send_progress(ctx, 0, 100)
    Process.sleep(50)
    ToolContext.send_progress(ctx, 50, 100)
    Process.sleep(50)
    ToolContext.send_progress(ctx, 100, 100)
    {:ok, [text("progress-token")], state}
  end

  def handle_call_tool("test_error_handling", _args, _ctx, state) do
    {:ok, [text("This tool intentionally returns an error for testing")], true, state}
  end

  # ---------------------------------------------------------------------------
  # Tools — SEP-2322 (MRTR)
  # ---------------------------------------------------------------------------

  def handle_call_tool("test_input_required_result_elicitation", _args, ctx, state) do
    mrtr(ctx, state, "elicitation", fn
      :first ->
        {:request, %{"user_name" => elicit("What is your name?", "name")}, %{}}

      {:retry, responses, _carried} ->
        case accepted_field(responses, "user_name", "name") do
          {:ok, name} -> {:complete, [text("Hello, #{name}!")]}
          :error -> {:request, %{"user_name" => elicit("What is your name?", "name")}, %{}}
        end
    end)
  end

  def handle_call_tool("test_input_required_result_sampling", _args, ctx, state) do
    mrtr(ctx, state, "sampling", fn
      :first ->
        {:request, %{"capital_question" => sample("What is the capital of France?")}, %{}}

      {:retry, responses, _carried} ->
        {:complete, [text("The model answered: #{sampling_text(responses, "capital_question")}")]}
    end)
  end

  def handle_call_tool("test_input_required_result_list_roots", _args, ctx, state) do
    mrtr(ctx, state, "list_roots", fn
      :first ->
        {:request, %{"client_roots" => roots_request()}, %{}}

      {:retry, responses, _carried} ->
        {:complete, [text("Client roots: #{roots_summary(responses, "client_roots")}")]}
    end)
  end

  def handle_call_tool("test_input_required_result_request_state", _args, ctx, state) do
    mrtr(ctx, state, "request_state", fn
      :first ->
        {:request, %{"confirm" => elicit_boolean("Please confirm", "ok")}, %{"issued" => "r1"}}

      {:retry, _responses, carried} ->
        # The scenario requires the word "state-ok" to prove the server both
        # received and *validated* the echoed state. `carried` is the verified
        # payload — reaching this clause at all means the tag checked out.
        {:complete, [text("state-ok (issued=#{Map.get(carried, "issued", "?")})")]}
    end)
  end

  def handle_call_tool("test_input_required_result_multiple_inputs", _args, ctx, state) do
    mrtr(ctx, state, "multiple_inputs", fn
      :first ->
        {:request,
         %{
           "user_name" => elicit("What is your name?", "name"),
           "greeting" => sample("Generate a greeting"),
           "client_roots" => roots_request()
         }, %{}}

      {:retry, responses, _carried} ->
        {:complete, [text("Collected #{map_size(responses_map(responses))} inputs")]}
    end)
  end

  def handle_call_tool("test_input_required_result_multi_round", _args, ctx, state) do
    mrtr(ctx, state, "multi_round", fn
      :first ->
        {:request, %{"step1" => elicit("Step 1: What is your name?", "name")}, %{"round" => 1}}

      {:retry, responses, %{"round" => 1}} ->
        name = responses |> accepted_field("step1", "name") |> ok_or("friend")

        {:request, %{"step2" => elicit("Step 2: What is your favorite color?", "color")},
         %{"round" => 2, "name" => name}}

      {:retry, responses, %{"round" => 2} = carried} ->
        color = responses |> accepted_field("step2", "color") |> ok_or("unknown")
        {:complete, [text("#{Map.get(carried, "name", "friend")} likes #{color}")]}

      {:retry, _responses, _carried} ->
        {:complete, [text("Unexpected round; completing")]}
    end)
  end

  def handle_call_tool("test_input_required_result_tampered_state", _args, ctx, state) do
    mrtr(ctx, state, "tampered_state", fn
      :first ->
        {:request, %{"confirm" => elicit_boolean("Please confirm", "ok")}, %{}}

      {:retry, _responses, _carried} ->
        {:complete, [text("state verified")]}
    end)
  end

  def handle_call_tool("test_input_required_result_capabilities", _args, ctx, state) do
    mrtr(ctx, state, "capabilities", fn
      :first ->
        # Only ask for what the client said it can do. The requests map is
        # built from the DECLARED capabilities rather than filtered afterwards,
        # so there is no branch in which an undeclared method survives.
        {:request, declared_input_requests(ctx), %{}}

      {:retry, _responses, _carried} ->
        {:complete, [text("capabilities honoured")]}
    end)
  end

  # ---------------------------------------------------------------------------
  # Tools — SEP-2575 diagnostics used by `server-stateless`
  # ---------------------------------------------------------------------------

  def handle_call_tool("test_missing_capability", _args, ctx, state) do
    if capability?(ctx, "sampling") do
      {:ok, [text("sampling capability was declared")], state}
    else
      # MUST be -32021 with `error.data.requiredCapabilities` = {"sampling":{}}.
      # The SDK's handler error return carries no `data`, so the code is right
      # and the data cannot be attached. Escalated, not worked around.
      {:error, -32_021,
       "Missing required client capability: sampling (requiredCapabilities: " <>
         Jason.encode!(%{"sampling" => %{}}) <> ")", state}
    end
  end

  def handle_call_tool("test_streaming_elicitation", _args, ctx, state) do
    mrtr(ctx, state, "streaming_elicitation", fn
      :first ->
        {:request, %{"stream_input" => elicit("Input requested mid-stream", "value")}, %{}}

      {:retry, _responses, _carried} ->
        {:complete, [text("stream input received")]}
    end)
  end

  def handle_call_tool("test_logging_tool", _args, ctx, state) do
    # The MUST NOT: no `notifications/message` unless this request authorised a
    # log level. The SDK never logs on a handler's behalf, so the decision is
    # here, read from this request's own `_meta`.
    case request_log_level(ctx) do
      nil -> :ok
      level -> ToolContext.log(ctx, level, "log level was authorised by _meta")
    end

    {:ok, [text("logging tool executed")], state}
  end

  def handle_call_tool("test_trigger_tool_change", _args, _ctx, state) do
    store_put(:tools_bumped, not store_get(:tools_bumped, false))
    broadcast("notifications/tools/list_changed", %{})
    {:ok, [text("tool list mutated")], state}
  end

  def handle_call_tool("test_trigger_prompt_change", _args, _ctx, state) do
    store_put(:prompts_bumped, not store_get(:prompts_bumped, false))
    broadcast("notifications/prompts/list_changed", %{})
    {:ok, [text("prompt list mutated")], state}
  end

  def handle_call_tool("test_dynamic_tool", _args, _ctx, state) do
    {:ok, [text("dynamic tool executed")], state}
  end

  def handle_call_tool("json_schema_2020_12_tool", args, _ctx, state) do
    {:ok, [text("2020-12 tool called with #{map_size(args)} argument(s)")], state}
  end

  def handle_call_tool("test_custom_header_tool", args, _ctx, state) do
    {:ok, [text("greeting=#{Map.get(args, "greeting", "")}")], state}
  end

  def handle_call_tool(name, _args, _ctx, state) do
    {:error, -32_602, "Unknown tool: #{name}", state}
  end

  # ---------------------------------------------------------------------------
  # MRTR plumbing
  # ---------------------------------------------------------------------------

  # One round-driver for every MRTR tool. `fun` is called with `:first` or
  # `{:retry, responses, verified_payload}` and answers `{:request, requests,
  # payload_to_carry}` or `{:complete, content}`.
  #
  # The continuation is derived from the request, never from a per-tool branch:
  # a tool cannot accidentally accept a token minted for a different tool,
  # because the tool name is inside the signed payload and compared here.
  defp mrtr(ctx, state, tool, fun) do
    case continuation(ctx, tool) do
      :first ->
        emit(fun.(:first), tool, state)

      {:ok, payload, responses} ->
        emit(fun.({:retry, responses, payload}), tool, state)

      {:error, reason} ->
        {:error, -32_602, "requestState failed integrity verification (#{reason})", state}
    end
  end

  defp emit({:request, requests, carried}, tool, state) do
    payload = Map.merge(carried, %{"tool" => tool})
    {:input_required, requests, RequestState.mint(signing_key(), payload), state}
  end

  defp emit({:complete, content}, _tool, state), do: {:ok, content, state}

  defp continuation(%{input: nil}, _tool), do: :first

  defp continuation(%{input: %{request_state: token, responses: responses}}, tool) do
    case RequestState.verify(signing_key(), token) do
      {:ok, %{"tool" => ^tool} = payload} -> {:ok, payload, responses}
      {:ok, %{"tool" => other}} -> {:error, "token minted for #{other}"}
      {:ok, _} -> {:error, "token payload missing its tool binding"}
      {:error, reason} -> {:error, to_string(reason)}
    end
  end

  defp continuation(_ctx, _tool), do: :first

  # --- input-request constructors (wire shapes, per schema InputRequest) ---

  defp elicit(message, field) do
    %{
      "method" => "elicitation/create",
      "params" => %{
        "message" => message,
        "requestedSchema" => %{
          "type" => "object",
          "properties" => %{field => %{"type" => "string"}},
          "required" => [field]
        }
      }
    }
  end

  defp elicit_boolean(message, field) do
    %{
      "method" => "elicitation/create",
      "params" => %{
        "message" => message,
        "requestedSchema" => %{
          "type" => "object",
          "properties" => %{field => %{"type" => "boolean"}},
          "required" => [field]
        }
      }
    }
  end

  defp sample(prompt) do
    %{
      "method" => "sampling/createMessage",
      "params" => %{
        "messages" => [%{"role" => "user", "content" => text(prompt)}],
        "maxTokens" => 100
      }
    }
  end

  defp roots_request, do: %{"method" => "roots/list", "params" => %{}}

  # --- client-capability reading (per-request `_meta`, never a server default) ---

  defp client_capabilities(%{meta: meta}) when is_map(meta) do
    Meta.from_meta(meta).client_capabilities || %{}
  end

  defp client_capabilities(_ctx), do: %{}

  defp capability?(ctx, name), do: Map.has_key?(client_capabilities(ctx), name)

  defp request_log_level(%{meta: meta}) when is_map(meta),
    do: Meta.from_meta(meta).log_level

  defp request_log_level(_ctx), do: nil

  defp declared_input_requests(ctx) do
    caps = client_capabilities(ctx)

    %{}
    |> maybe_put(caps, "elicitation", "user_name", fn -> elicit("What is your name?", "name") end)
    |> maybe_put(caps, "sampling", "greeting", fn -> sample("Generate a greeting") end)
    |> maybe_put(caps, "roots", "client_roots", fn -> roots_request() end)
  end

  defp maybe_put(requests, caps, capability, key, build) do
    if Map.has_key?(caps, capability), do: Map.put(requests, key, build.()), else: requests
  end

  # --- InputResponses readers ---

  defp responses_map(responses) when is_map(responses), do: responses
  defp responses_map(_), do: %{}

  defp accepted_field(responses, key, field) do
    case responses |> responses_map() |> Map.get(key) do
      %{"action" => "accept", "content" => %{^field => value}} -> {:ok, value}
      _ -> :error
    end
  end

  defp ok_or({:ok, value}, _default), do: value
  defp ok_or(:error, default), do: default

  defp sampling_text(responses, key) do
    case responses |> responses_map() |> Map.get(key) do
      %{"content" => %{"text" => text}} -> text
      other -> inspect(other)
    end
  end

  defp roots_summary(responses, key) do
    case responses |> responses_map() |> Map.get(key) do
      %{"roots" => roots} when is_list(roots) ->
        roots |> Enum.map_join(", ", &Map.get(&1, "uri", "?"))

      other ->
        inspect(other)
    end
  end

  defp text(value), do: %{"type" => "text", "text" => value}

  # ---------------------------------------------------------------------------
  # Resources
  # ---------------------------------------------------------------------------

  @impl true
  def handle_list_resources(_cursor, _ctx, state) do
    resources = [
      %{
        "uri" => "test://static-text",
        "name" => "Static Text Resource",
        "description" => "A static text resource for conformance testing",
        "mimeType" => "text/plain"
      },
      %{
        "uri" => "test://static-binary",
        "name" => "Static Binary Resource",
        "description" => "A static binary resource for conformance testing",
        "mimeType" => "image/png"
      },
      %{
        "uri" => "test://watched-resource",
        "name" => "Watched Resource",
        "description" => "A resource used for change notifications",
        "mimeType" => "text/plain"
      }
    ]

    {:ok, resources, nil, state}
  end

  @impl true
  def handle_read_resource("test://static-text", _ctx, state) do
    {:ok,
     [
       %{
         "uri" => "test://static-text",
         "mimeType" => "text/plain",
         "text" => "This is the content of the static text resource."
       }
     ], state}
  end

  def handle_read_resource("test://static-binary", _ctx, state) do
    {:ok,
     [
       %{
         "uri" => "test://static-binary",
         "mimeType" => "image/png",
         "blob" => @test_image_base64
       }
     ], state}
  end

  def handle_read_resource("test://watched-resource", _ctx, state) do
    {:ok,
     [
       %{
         "uri" => "test://watched-resource",
         "mimeType" => "text/plain",
         "text" => "Watched resource content"
       }
     ], state}
  end

  def handle_read_resource("test://template/" <> rest, _ctx, state) do
    id = rest |> String.split("/") |> hd()

    {:ok,
     [
       %{
         "uri" => "test://template/#{id}/data",
         "mimeType" => "application/json",
         "text" =>
           Jason.encode!(%{"id" => id, "templateTest" => true, "data" => "Data for ID: #{id}"})
       }
     ], state}
  end

  # SEP-2164: an unknown URI is -32602 with the requested uri in `data` — which
  # the handler error return cannot carry (see the moduledoc's gap list), so
  # the code is right and the `data.uri` SHOULD is unmet.
  def handle_read_resource(uri, _ctx, state) do
    {:error, -32_602, "Resource not found: #{uri}", state}
  end

  @impl true
  def handle_list_resource_templates(_cursor, _ctx, state) do
    templates = [
      %{
        "uriTemplate" => "test://template/{id}/data",
        "name" => "Template Resource",
        "description" => "A resource template with ID parameter",
        "mimeType" => "application/json"
      }
    ]

    {:ok, templates, nil, state}
  end

  # ---------------------------------------------------------------------------
  # Prompts
  # ---------------------------------------------------------------------------

  @impl true
  def handle_list_prompts(_cursor, _ctx, state) do
    prompts =
      [
        %{"name" => "test_simple_prompt", "description" => "Simple prompt without arguments"},
        %{
          "name" => "test_prompt_with_arguments",
          "description" => "Prompt with arguments",
          "arguments" => [
            %{"name" => "arg1", "description" => "First test argument", "required" => true},
            %{"name" => "arg2", "description" => "Second test argument", "required" => true}
          ]
        },
        %{
          "name" => "test_prompt_with_embedded_resource",
          "description" => "Prompt with embedded resource",
          "arguments" => [
            %{
              "name" => "resourceUri",
              "description" => "URI of the resource to embed",
              "required" => true
            }
          ]
        },
        %{"name" => "test_prompt_with_image", "description" => "Prompt with image content"},
        %{
          "name" => "test_input_required_result_prompt",
          "description" => "SEP-2322 MRTR on a non-tool request"
        }
      ] ++ dynamic_prompts()

    {:ok, prompts, nil, state}
  end

  defp dynamic_prompts do
    if store_get(:prompts_bumped, false) do
      [%{"name" => "test_dynamic_prompt", "description" => "Added by test_trigger_prompt_change"}]
    else
      []
    end
  end

  @impl true
  def handle_get_prompt("test_simple_prompt", _args, _ctx, state) do
    {:ok, %{"messages" => [user_message(text("This is a simple prompt for testing."))]}, state}
  end

  def handle_get_prompt("test_prompt_with_arguments", args, _ctx, state) do
    arg1 = Map.get(args || %{}, "arg1", "")
    arg2 = Map.get(args || %{}, "arg2", "")

    {:ok,
     %{
       "messages" => [
         user_message(text("Prompt with arguments: arg1='#{arg1}', arg2='#{arg2}'"))
       ]
     }, state}
  end

  def handle_get_prompt("test_prompt_with_embedded_resource", args, _ctx, state) do
    uri = Map.get(args || %{}, "resourceUri", "test://example-resource")

    {:ok,
     %{
       "messages" => [
         user_message(%{
           "type" => "resource",
           "resource" => %{
             "uri" => uri,
             "mimeType" => "text/plain",
             "text" => "Embedded resource content for testing."
           }
         }),
         user_message(text("Please process the embedded resource above."))
       ]
     }, state}
  end

  def handle_get_prompt("test_prompt_with_image", _args, _ctx, state) do
    {:ok,
     %{
       "messages" => [
         user_message(%{
           "type" => "image",
           "data" => @test_image_base64,
           "mimeType" => "image/png"
         }),
         user_message(text("Please analyze the image above."))
       ]
     }, state}
  end

  # SEP-2322 on a non-tool request. `MCP.Server.Dispatch` neither populates
  # `ctx.input` for `prompts/get` nor accepts an `{:input_required, …}` return
  # from it, so this is the input-required body sent down the only channel the
  # SDK leaves open — `{:ok, result, state}`, whose `resultType` the dispatch
  # then overwrites with `"complete"`. Written this way deliberately: it puts
  # the gap on the wire where the harness can see it, instead of raising a
  # `FunctionClauseError` inside a server shared by 37 scenarios. The raise is
  # measured, not assumed: returning `{:input_required, …}` from this callback
  # gives "no function clause matching in anonymous fn/1 in
  # MCP.Server.Dispatch.route/5", with the same return from a `tools/call`
  # handler as the passing positive control (docs/sprint_4_issues.md).
  def handle_get_prompt("test_input_required_result_prompt", _args, _ctx, state) do
    {:ok,
     %{
       "resultType" => "input_required",
       "inputRequests" => %{
         "user_context" => elicit("What context should the prompt use?", "context")
       }
     }, state}
  end

  def handle_get_prompt(name, _args, _ctx, state) do
    {:error, -32_602, "Unknown prompt: #{name}", state}
  end

  defp user_message(content), do: %{"role" => "user", "content" => content}

  # ---------------------------------------------------------------------------
  # Completion
  # ---------------------------------------------------------------------------

  @impl true
  def handle_complete(_ref, _argument, _ctx, state) do
    {:ok, %{"values" => [], "total" => 0, "hasMore" => false}, state}
  end

  # ---------------------------------------------------------------------------
  # Subscriptions
  # ---------------------------------------------------------------------------

  @impl true
  def supported_subscriptions do
    ["toolsListChanged", "promptsListChanged", "resourcesListChanged"]
  end

  @impl true
  def handle_listen(filter, ctx, state) do
    store_put({:stream, ctx.request_id}, ctx.stream_sink)
    {:ok, filter, state}
  end

  @impl true
  def handle_listen_closed(subscription_id, _ctx, state) do
    :ets.delete(ensure_store(), {:stream, subscription_id})
    {:ok, state}
  end
end
