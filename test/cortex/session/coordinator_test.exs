defmodule Cortex.Session.CoordinatorTest do
  use Cortex.DataCase, async: false

  import Cortex.ConversationsFixtures

  alias Cortex.Agents.LLMAgent
  alias Cortex.Conversations
  alias Cortex.Session.Coordinator

  describe "session_id/1" do
    test "returns the session id mapping" do
      assert Coordinator.session_id("abc") == "session_abc"
    end
  end

  describe "ensure_session/2" do
    test "starts a session when missing" do
      conversation = conversation_fixture()

      {:ok, session} =
        Coordinator.ensure_session(conversation.id, model: "gemini-3-flash")

      on_exit(fn ->
        Coordinator.stop_session(conversation.id)
      end)

      assert session.session_id == Coordinator.session_id(conversation.id)
      assert is_pid(session.pid)
      assert LLMAgent.whereis(session.session_id) == session.pid
    end
  end

  describe "stop_session/1" do
    test "stops the session and persists state" do
      conversation = conversation_fixture()

      {:ok, _session} =
        Coordinator.ensure_session(conversation.id, model: "gemini-3-flash")

      assert {:ok, :stopped} = Coordinator.stop_session(conversation.id)
      assert LLMAgent.whereis(Coordinator.session_id(conversation.id)) == nil

      reloaded = Conversations.get_conversation!(conversation.id)
      assert is_list(reloaded.llm_context)
    end
  end

  describe "save_state/2" do
    test "returns error when session not running" do
      conversation = conversation_fixture()
      assert {:error, :not_running} = Coordinator.save_state(conversation.id)
    end
  end

  describe "switch_session/3" do
    test "starts a new session and keeps old running" do
      old_conversation = conversation_fixture()
      new_conversation = conversation_fixture()

      {:ok, _session} =
        Coordinator.ensure_session(old_conversation.id, model: "gemini-3-flash")

      {:ok, session} =
        Coordinator.switch_session(old_conversation.id, new_conversation.id,
          model: "gemini-3-flash"
        )

      on_exit(fn ->
        Coordinator.stop_session(old_conversation.id)
        Coordinator.stop_session(new_conversation.id)
      end)

      assert session.session_id == Coordinator.session_id(new_conversation.id)
      assert Coordinator.running?(old_conversation.id)
      assert Coordinator.running?(new_conversation.id)
    end
  end
end
