defmodule Cortex.ConversationsDisplayTest do
  use Cortex.DataCase

  alias Cortex.Conversations
  alias Cortex.ConversationsFixtures

  test "append_text_message stores display message" do
    conversation = ConversationsFixtures.conversation_fixture()

    assert {:ok, message} =
             Conversations.append_text_message(conversation.id, "user", "hello")

    assert message.message_type == "user"
    assert message.content_type == "text"
    assert message.content["text"] == "hello"
  end

  test "tool call lifecycle updates status and stores result" do
    conversation = ConversationsFixtures.conversation_fixture()

    assert {:ok, call} =
             Conversations.append_tool_call_message(
               conversation.id,
               "call_1",
               "read_file",
               %{"path" => "README.md"}
             )

    assert call.status == "pending"

    assert {:ok, updated} = Conversations.complete_tool_call("call_1", %{"result" => "ok"})
    assert updated.status == "completed"
    assert updated.metadata["result"] == "ok"

    assert {:ok, result} =
             Conversations.append_tool_result_message(
               conversation.id,
               "call_1",
               "read_file",
               "content"
             )

    assert result.content_type == "tool_result"
    assert result.content["tool_call_id"] == "call_1"
  end
end
