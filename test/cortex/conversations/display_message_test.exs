defmodule Cortex.Conversations.DisplayMessageTest do
  use Cortex.DataCase

  alias Cortex.Conversations.DisplayMessage
  alias Cortex.ConversationsFixtures

  describe "changesets" do
    test "validates text content" do
      conversation = ConversationsFixtures.conversation_fixture()

      changeset =
        DisplayMessage.create_changeset(conversation.id, %{
          message_type: "user",
          content_type: "text",
          content: %{"text" => "hello"}
        })

      assert changeset.valid?
    end

    test "rejects invalid tool_call content" do
      conversation = ConversationsFixtures.conversation_fixture()

      changeset =
        DisplayMessage.create_changeset(conversation.id, %{
          message_type: "assistant",
          content_type: "tool_call",
          content: %{"name" => "read_file"}
        })

      refute changeset.valid?
      assert "invalid structure for content_type tool_call" in errors_on(changeset).content
    end
  end
end
