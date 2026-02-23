defmodule Cortex.ConversationsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Cortex.Conversations` context.
  """

  alias Cortex.WorkspacesFixtures

  @doc """
  Generate a conversation.
  """
  def conversation_fixture(attrs \\ %{}) do
    workspace = WorkspacesFixtures.workspace_fixture()

    {:ok, conversation} =
      Cortex.Conversations.create_conversation(
        attrs
        |> Enum.into(%{
          context: %{},
          status: "active",
          title: "some title"
        }),
        workspace.id
      )

    conversation
  end

  @doc """
  Generate a display message.
  """
  def display_message_fixture(attrs \\ %{}) do
    conversation = conversation_fixture()

    message_type = Map.get(attrs, :message_type, "user")
    text = Map.get(attrs, :text, "some content")

    {:ok, message} =
      Cortex.Conversations.append_text_message(conversation.id, message_type, text)

    message
  end
end
