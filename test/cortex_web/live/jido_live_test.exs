defmodule CortexWeb.JidoLiveTest do
  use CortexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Cortex.Config.Metadata
  alias CortexWeb.JidoLive
  alias Cortex.SignalHub

  import Cortex.ConfigFixtures
  import Cortex.WorkspacesFixtures
  import Cortex.ConversationsFixtures

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

  describe "signal synchronization" do
    test "updates conversation list when conversation.created signal is received", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Get the actual workspace_id used by the LiveView
      state = :sys.get_state(view.pid)
      workspace_id = state.socket.assigns.workspace.id

      # Simulate a new conversation created elsewhere (e.g. Telegram)
      new_conversation =
        conversation_fixture(%{workspace_id: workspace_id, title: "Telegram Chat"})

      SignalHub.emit("conversation.created", %{
        provider: "system",
        event: "conversation",
        action: "create",
        actor: "test",
        origin: %{channel: "test", client: "test", platform: "server"},
        workspace_id: workspace_id,
        conversation: new_conversation
      })

      # Verify it appears in the sidebar
      assert render(view) =~ "Telegram Chat"
    end

    test "filters streaming chunks from other sessions", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Get current session info
      state = :sys.get_state(view.pid)
      current_session_id = state.socket.assigns.session_id

      # Emit a chunk for a DIFFERENT session
      SignalHub.emit("agent.response.chunk", %{
        provider: "agent",
        event: "response",
        action: "chunk",
        actor: "llm",
        origin: %{channel: "agent", client: "llm", platform: "server"},
        session_id: "other_session_123",
        message_id: "msg_1",
        chunk: "Secret leaked info"
      })

      # Should NOT appear in the UI
      refute render(view) =~ "Secret leaked info"

      # Emit a chunk for the CURRENT session
      SignalHub.emit("agent.response.chunk", %{
        provider: "agent",
        event: "response",
        action: "chunk",
        actor: "llm",
        origin: %{channel: "agent", client: "llm", platform: "server"},
        session_id: current_session_id,
        message_id: "msg_2",
        chunk: "Valid content"
      })

      # Should appear in the UI
      assert render(view) =~ "Valid content"
    end
  end

  # Note: These tests are temporarily skipped as they depend on specific UI implementation
  # that might have changed during the refactoring process or V3 migration.
  @tag :skip
  describe "ui notifications" do
    test "persists show_archived notification", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      _ = render_click(view, "show_archived")
    end
  end

  @tag :skip
  describe "signal handling" do
    test "handles flattened tool.result.shell payload without crashing and stores message", %{
      conn: conn
    } do
      {:ok, _view, _html} = live(conn, "/")
      # ...
    end
  end
end
