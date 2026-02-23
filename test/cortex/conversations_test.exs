defmodule Cortex.ConversationsTest do
  use Cortex.DataCase

  import Ecto.Query

  alias Cortex.Conversations
  alias Cortex.Conversations.DisplayMessage
  alias Cortex.Repo
  alias Cortex.WorkspacesFixtures

  describe "conversations" do
    alias Cortex.Conversations.Conversation

    import Cortex.ConversationsFixtures

    @invalid_attrs %{status: nil, context: nil, title: nil}

    test "list_conversations/1 returns active conversations for a workspace" do
      workspace = WorkspacesFixtures.workspace_fixture()
      conversation = conversation_fixture(%{title: "Workspace Conversation"})

      assert Conversations.list_conversations(workspace.id) == []

      {:ok, workspace_conv} =
        Conversations.create_conversation(%{title: "Workspace Conversation"}, workspace.id)

      assert Conversations.list_conversations(workspace.id) == [workspace_conv]
      refute conversation.id == workspace_conv.id
    end

    test "get_conversation!/1 returns the conversation with given id" do
      conversation = conversation_fixture()
      assert Conversations.get_conversation!(conversation.id) == conversation
    end

    test "create_conversation/2 with valid data creates a conversation" do
      workspace = WorkspacesFixtures.workspace_fixture()

      valid_attrs = %{
        status: "active",
        context: %{},
        title: "some title"
      }

      assert {:ok, %Conversation{} = conversation} =
               Conversations.create_conversation(valid_attrs, workspace.id)

      assert conversation.status == "active"
      assert conversation.context == %{}
      assert conversation.title == "some title"
      assert conversation.workspace_id == workspace.id
      assert conversation.last_used_at

      messages = Conversations.load_display_messages(conversation.id)

      assert Enum.any?(messages, fn msg ->
               msg.content_type == "text" and
                 msg.content["text"] == Conversations.welcome_message()
             end)
    end

    test "create_conversation/2 emits conversation.created signal" do
      workspace = WorkspacesFixtures.workspace_fixture()
      Cortex.SignalHub.subscribe("conversation.created")

      assert {:ok, %Conversation{} = conversation} =
               Conversations.create_conversation(%{title: "Signal Test"}, workspace.id)

      assert_receive {:signal, %Jido.Signal{type: "conversation.created", data: data}}
      payload = data.payload
      assert payload.workspace_id == workspace.id
      assert payload.conversation.id == conversation.id
    end

    test "create_conversation/2 with invalid data returns error changeset" do
      workspace = WorkspacesFixtures.workspace_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Conversations.create_conversation(@invalid_attrs, workspace.id)
    end

    test "update_conversation/2 with valid data updates the conversation" do
      conversation = conversation_fixture()

      update_attrs = %{
        status: "archived",
        context: %{},
        title: "some updated title"
      }

      assert {:ok, %Conversation{} = conversation} =
               Conversations.update_conversation(conversation, update_attrs)

      assert conversation.status == "archived"
      assert conversation.context == %{}
      assert conversation.title == "some updated title"
    end

    test "update_conversation/2 with invalid data returns error changeset" do
      conversation = conversation_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Conversations.update_conversation(conversation, @invalid_attrs)

      assert conversation == Conversations.get_conversation!(conversation.id)
    end

    test "delete_conversation/1 deletes the conversation" do
      conversation = conversation_fixture()
      assert {:ok, %Conversation{}} = Conversations.delete_conversation(conversation)
      assert_raise Ecto.NoResultsError, fn -> Conversations.get_conversation!(conversation.id) end
    end

    test "delete_conversation/1 removes related display messages" do
      conversation = conversation_fixture()

      {:ok, _} = Conversations.append_text_message(conversation.id, "user", "Hi")

      assert {:ok, %Conversation{}} = Conversations.delete_conversation(conversation)

      remaining =
        from(m in DisplayMessage, where: m.conversation_id == ^conversation.id)
        |> Repo.aggregate(:count, :id)

      assert remaining == 0
    end

    test "touch_conversation/1 updates last_used_at" do
      conversation = conversation_fixture(%{last_used_at: nil})

      assert {:ok, %Conversation{} = touched} = Conversations.touch_conversation(conversation)
      assert touched.last_used_at
    end

    test "archive_conversation/1 marks conversation as archived" do
      conversation = conversation_fixture()

      assert {:ok, %Conversation{status: "archived"}} =
               Conversations.archive_conversation(conversation)
    end

    test "list_archived_conversations/1 returns only archived conversations" do
      workspace = WorkspacesFixtures.workspace_fixture()
      {:ok, active} = Conversations.create_conversation(%{title: "Active"}, workspace.id)

      {:ok, archived} =
        Conversations.create_conversation(%{title: "Archived", status: "archived"}, workspace.id)

      archived_list = Conversations.list_archived_conversations(workspace.id)
      assert length(archived_list) == 1
      assert hd(archived_list).id == archived.id
    end

    test "count_archived/1 returns the number of archived conversations" do
      workspace = WorkspacesFixtures.workspace_fixture()
      assert Conversations.count_archived(workspace.id) == 0

      {:ok, _} =
        Conversations.create_conversation(
          %{title: "Archived 1", status: "archived"},
          workspace.id
        )

      assert Conversations.count_archived(workspace.id) == 1

      {:ok, _} =
        Conversations.create_conversation(
          %{title: "Archived 2", status: "archived"},
          workspace.id
        )

      assert Conversations.count_archived(workspace.id) == 2
    end

    test "restore_conversation/1 marks conversation as active" do
      conversation = conversation_fixture(%{status: "archived"})

      assert {:ok, %Conversation{status: "active"}} =
               Conversations.restore_conversation(conversation)
    end

    test "change_conversation/1 returns a conversation changeset" do
      conversation = conversation_fixture()
      assert %Ecto.Changeset{} = Conversations.change_conversation(conversation)
    end
  end

  describe "display_messages" do
    alias Cortex.Conversations.DisplayMessage

    import Cortex.ConversationsFixtures

    @invalid_attrs %{message_type: nil, content_type: nil, content: nil}

    test "load_display_messages/1 returns conversation messages" do
      message = display_message_fixture()
      messages = Conversations.load_display_messages(message.conversation_id)

      assert Enum.any?(messages, &(&1.id == message.id))

      assert Enum.any?(messages, fn msg ->
               msg.content_type == "text" and
                 msg.content["text"] == Conversations.welcome_message()
             end)
    end

    test "preload display messages through conversation association" do
      conversation = conversation_fixture()

      {:ok, _} = Conversations.append_text_message(conversation.id, "user", "Hello")

      conversation = Repo.preload(conversation, :display_messages)

      assert Enum.any?(conversation.display_messages, &(&1.conversation_id == conversation.id))
    end

    test "append_display_message/2 with valid data creates a message" do
      conversation = conversation_fixture()

      valid_attrs = %{
        message_type: "user",
        content_type: "text",
        content: %{"text" => "some content"}
      }

      assert {:ok, %DisplayMessage{} = message} =
               Conversations.append_display_message(conversation.id, valid_attrs)

      assert message.content_type == "text"
      assert message.message_type == "user"
      assert message.content["text"] == "some content"
    end

    test "append_display_message/2 with invalid data returns error changeset" do
      conversation = conversation_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Conversations.append_display_message(conversation.id, @invalid_attrs)
    end

    test "get_history/2 returns truncated history" do
      conversation = conversation_fixture()

      {:ok, _} = Conversations.append_text_message(conversation.id, "user", "one")
      {:ok, _} = Conversations.append_text_message(conversation.id, "assistant", "two")

      history = Conversations.get_history(conversation.id, max_messages: 1)
      assert history == [%{role: "assistant", content: "two"}]
    end
  end
end
