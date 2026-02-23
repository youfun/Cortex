defmodule CortexWeb.AgentLiveHelpersTest do
  use CortexWeb.ConnCase, async: true

  alias CortexWeb.AgentLiveHelpers
  alias CortexWeb.PermissionHelpers

  describe "file_context_message/2" do
    test "builds a system message with file content" do
      relative = "notes/readme.md"
      content = "Hello from file."

      msg = AgentLiveHelpers.file_context_message(relative, content)

      assert msg.role == "system"
      assert msg.content =~ relative
      assert msg.content =~ content
    end
  end

  describe "parse_decision/1" do
    test "parses known decisions" do
      assert PermissionHelpers.parse_decision("allow") == :allow
      assert PermissionHelpers.parse_decision("allow_always") == :allow_always
      assert PermissionHelpers.parse_decision("deny") == :deny
    end

    test "defaults to deny for unknown inputs" do
      assert PermissionHelpers.parse_decision("maybe") == :deny
      assert PermissionHelpers.parse_decision(nil) == :deny
    end
  end

  describe "belongs_to_session?/2" do
    test "matches session_id in payload" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{current_conversation_id: "conv_1", session_id: "session_1"}
      }

      {:ok, signal} =
        Jido.Signal.new(
          "agent.response",
          %{session_id: "session_1"},
          source: "/tests/agent_live_helpers"
        )

      assert AgentLiveHelpers.belongs_to_session?(signal, socket)
    end

    test "matches session_id in origin" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{current_conversation_id: "conv_1", session_id: "session_1"}
      }

      {:ok, signal} =
        Jido.Signal.new(
          "agent.response",
          %{origin: %{session_id: "session_1"}},
          source: "/tests/agent_live_helpers"
        )

      assert AgentLiveHelpers.belongs_to_session?(signal, socket)
    end
  end
end
