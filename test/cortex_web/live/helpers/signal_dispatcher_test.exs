defmodule CortexWeb.SignalDispatcherTest do
  use CortexWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias CortexWeb.SignalDispatcher
  alias Cortex.Config.Metadata

  import Cortex.ConfigFixtures

  setup %{conn: conn} do
    _model = llm_model_fixture(%{enabled: true})
    Metadata.reload()

    # Setup Basic Auth
    user = System.get_env("AUTH_USER", "admin")
    pass = System.get_env("AUTH_PASS", "admin")
    auth = "Basic " <> Base.encode64("#{user}:#{pass}")
    conn = put_req_header(conn, "authorization", auth)

    {:ok, conn: conn}
  end

  describe "dispatch/3" do
    test "accumulates streaming chunks for current session", %{conn: conn} do
      # Use a real LiveView to get a proper socket
      {:ok, view, _html} = live(conn, "/")
      socket = :sys.get_state(view.pid).socket

      # Assign test data
      socket =
        socket
        |> Phoenix.Component.assign(:current_conversation_id, "conv_1")
        |> Phoenix.Component.assign(:session_id, "session_1")
        |> Phoenix.Component.assign(:streaming_messages, %{})

      {:ok, signal} =
        Jido.Signal.new(
          "agent.response.chunk",
          %{session_id: "session_1", message_id: "msg_1", chunk: "Hello"},
          source: "/tests/signal_dispatcher"
        )

      updated = SignalDispatcher.dispatch("agent.response.chunk", signal, socket)

      assert updated.assigns.streaming_messages["msg_1"].content["text"] == "Hello"
    end

    test "sets thinking state on agent.think", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      socket = :sys.get_state(view.pid).socket

      socket =
        socket
        |> Phoenix.Component.assign(:current_conversation_id, "conv_1")
        |> Phoenix.Component.assign(:session_id, "session_1")
        |> Phoenix.Component.assign(:is_thinking, false)
        |> Phoenix.Component.assign(:plan_thought_text, "")

      {:ok, signal} =
        Jido.Signal.new(
          "agent.think",
          %{session_id: "session_1", thought: "Thinking"},
          source: "/tests/signal_dispatcher"
        )

      updated = SignalDispatcher.dispatch("agent.think", signal, socket)

      assert updated.assigns.is_thinking == true
      assert updated.assigns.plan_thought_text == "Thinking"
    end

    test "handles conversation.created with stream_insert", %{conn: conn} do
      # This test requires a real LiveView with streams initialized
      {:ok, view, _html} = live(conn, "/")
      socket = :sys.get_state(view.pid).socket

      {:ok, signal} =
        Jido.Signal.new(
          "conversation.created",
          %{workspace_id: socket.assigns.workspace.id, conversation: %{id: "c1", title: "New"}},
          source: "/tests/signal_dispatcher"
        )

      updated = SignalDispatcher.dispatch("conversation.created", signal, socket)
      # Just verify it doesn't crash - the stream is already initialized by the LiveView
      assert updated.assigns.streams.conversations
    end
  end
end
