defmodule MCP.Protocol.MethodsTest do
  use ExUnit.Case, async: true

  alias MCP.Protocol.Methods

  test "request methods" do
    assert Methods.initialize() == "initialize"
    assert Methods.ping() == "ping"
    assert Methods.tools_list() == "tools/list"
    assert Methods.tools_call() == "tools/call"
    assert Methods.resources_list() == "resources/list"
    assert Methods.resources_read() == "resources/read"
    assert Methods.resources_templates_list() == "resources/templates/list"
    assert Methods.prompts_list() == "prompts/list"
    assert Methods.prompts_get() == "prompts/get"
    assert Methods.logging_set_level() == "logging/setLevel"
    assert Methods.completion_complete() == "completion/complete"
    assert Methods.subscriptions_listen() == "subscriptions/listen"
  end

  test "resources/subscribe and resources/unsubscribe are gone, not renamed" do
    # Retired with the rest of the subscribe surface (MES-15): 2026-07-28
    # replaces both RPCs with the resourceSubscriptions field of a
    # subscriptions/listen filter (schema.ts:1286-1288). Asserted as an absence
    # so a future reader re-adding a constant has to argue with a test.
    refute function_exported?(Methods, :resources_subscribe, 0)
    refute function_exported?(Methods, :resources_unsubscribe, 0)
  end

  test "server-to-client request methods" do
    assert Methods.sampling_create_message() == "sampling/createMessage"
    assert Methods.roots_list() == "roots/list"
    assert Methods.elicitation_create() == "elicitation/create"
  end

  test "notification methods" do
    assert Methods.initialized() == "notifications/initialized"
    assert Methods.cancelled() == "notifications/cancelled"
    assert Methods.progress() == "notifications/progress"
    assert Methods.logging_message() == "notifications/message"
    assert Methods.tools_list_changed() == "notifications/tools/list_changed"
    assert Methods.resources_list_changed() == "notifications/resources/list_changed"
    assert Methods.resources_updated() == "notifications/resources/updated"
    assert Methods.prompts_list_changed() == "notifications/prompts/list_changed"
    assert Methods.roots_list_changed() == "notifications/roots/list_changed"
  end
end
