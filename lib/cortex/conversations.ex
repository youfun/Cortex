defmodule Cortex.Conversations do
  @moduledoc """
  The Conversations context.
  """

  import Ecto.Query, warn: false
  alias Cortex.Repo

  alias Cortex.Conversations.{Conversation, DisplayMessage}

  @welcome_message "Welcome to Cortex! How can I help you today?"

  # ========== Conversation Management ==========

  @doc """
  List active conversations for a workspace, ordered by pinned + recent use.
  """
  def list_conversations(workspace_id) do
    from(c in Conversation,
      where: c.workspace_id == ^workspace_id and c.status == "active",
      order_by: [desc: c.is_pinned, desc: c.last_used_at, desc: c.updated_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single conversation.
  """
  def get_conversation!(id), do: Repo.get!(Conversation, id)

  def get_conversation(id), do: Repo.get(Conversation, id)

  @doc """
  Gets a conversation by meta key/value.
  """
  def get_conversation_by_meta(key, value) when is_binary(key) do
    from(c in Conversation, where: c.meta[^key] == ^value, limit: 1)
    |> Repo.one()
  end

  @doc """
  Creates a conversation for a workspace.
  """
  def create_conversation(attrs \\ %{}, workspace_id) do
    Repo.transaction(fn ->
      with {:ok, conversation} <-
             %Conversation{
               workspace_id: workspace_id,
               last_used_at: now_utc()
             }
             |> Conversation.changeset(attrs)
             |> Repo.insert(),
           {:ok, _message} <- create_welcome_message(conversation) do
        emit_conversation_created(conversation)
        conversation
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp emit_conversation_created(conversation) do
    Cortex.SignalHub.emit(
      "conversation.created",
      %{
        provider: "system",
        event: "conversation",
        action: "create",
        actor: "conversation_context",
        origin: %{channel: "system", client: "conversation_context", platform: "server"},
        workspace_id: conversation.workspace_id,
        conversation: conversation
      },
      source: "/conversations"
    )
  end

  @doc """
  Gets or creates a conversation by meta key/value.
  """
  def get_or_create_by_meta(key, value, workspace_id, attrs \\ %{})
      when is_binary(key) do
    case get_conversation_by_meta(key, value) do
      %Conversation{} = convo ->
        {:ok, convo}

      nil ->
        meta = Map.merge(attrs[:meta] || %{}, %{key => value})

        create_conversation(
          Map.merge(
            %{
              title: attrs[:title] || "Conversation #{value}",
              status: attrs[:status] || "active",
              meta: meta
            },
            Map.drop(attrs, [:meta, :title, :status])
          ),
          workspace_id
        )
    end
  end

  @doc """
  Updates a conversation.
  """
  def update_conversation(%Conversation{} = conversation, attrs) do
    conversation
    |> Conversation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Soft archive a conversation.
  """
  def archive_conversation(%Conversation{} = conversation) do
    update_conversation(conversation, %{status: "archived"})
  end

  @doc """
  Update conversation last_used_at.
  """
  def touch_conversation(%Conversation{} = conversation) do
    case conversation
         |> Conversation.changeset(%{last_used_at: now_utc()})
         |> Repo.update() do
      {:ok, updated} ->
        emit_conversation_updated(updated)
        {:ok, updated}

      error ->
        error
    end
  end

  defp emit_conversation_updated(conversation) do
    Cortex.SignalHub.emit(
      "conversation.updated",
      %{
        provider: "system",
        event: "conversation",
        action: "update",
        actor: "conversation_context",
        origin: %{channel: "system", client: "conversation_context", platform: "server"},
        workspace_id: conversation.workspace_id,
        conversation: conversation
      },
      source: "/conversations"
    )
  end

  @doc """
  Deletes a conversation.
  """
  def delete_conversation(%Conversation{} = conversation) do
    Repo.delete(conversation)
  end

  @doc """
  Returns a changeset for tracking conversation changes.
  """
  def change_conversation(%Conversation{} = conversation, attrs \\ %{}) do
    Conversation.changeset(conversation, attrs)
  end

  @doc """
  List archived conversations for a workspace.
  """
  def list_archived_conversations(workspace_id) do
    from(c in Conversation,
      where: c.workspace_id == ^workspace_id and c.status == "archived",
      order_by: [desc: c.updated_at]
    )
    |> Repo.all()
  end

  @doc """
  Count archived conversations in a workspace.
  """
  def count_archived(workspace_id) do
    Repo.one(
      from c in Conversation,
        where: c.workspace_id == ^workspace_id and c.status == "archived",
        select: count(c.id)
    )
  end

  @doc """
  Restore an archived conversation to active status.
  """
  def restore_conversation(%Conversation{} = conversation) do
    update_conversation(conversation, %{status: "active"})
  end

  # ========== Display Messages ==========

  def append_display_message(conversation_id, attrs) do
    conversation_id
    |> DisplayMessage.create_changeset(attrs)
    |> Repo.insert()
  end

  def load_display_messages(conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    DisplayMessage
    |> where([m], m.conversation_id == ^conversation_id)
    |> order_by([m], asc: m.inserted_at, asc: m.sequence)
    |> limit(^limit)
    |> Repo.all()
  end

  def append_text_message(conversation_id, message_type, text) do
    append_display_message(conversation_id, %{
      message_type: message_type,
      content_type: "text",
      content: %{"text" => text}
    })
  end

  def append_thinking_message(conversation_id, text) do
    append_display_message(conversation_id, %{
      message_type: "assistant",
      content_type: "thinking",
      content: %{"text" => text}
    })
  end

  def append_tool_call_message(conversation_id, call_id, tool_name, arguments) do
    append_display_message(conversation_id, %{
      message_type: "assistant",
      content_type: "tool_call",
      status: "pending",
      content: %{"call_id" => call_id, "name" => tool_name, "arguments" => arguments}
    })
  end

  def append_tool_result_message(
        conversation_id,
        call_id,
        tool_name,
        result_content,
        is_error \\ false
      ) do
    append_display_message(conversation_id, %{
      message_type: "tool",
      content_type: "tool_result",
      content: %{
        "tool_call_id" => call_id,
        "name" => tool_name,
        "content" => result_content,
        "is_error" => is_error
      }
    })
  end

  def mark_tool_executing(call_id) do
    query =
      from m in DisplayMessage,
        where: fragment("json_extract(?, '$.call_id') = ?", m.content, ^call_id),
        where: m.content_type == "tool_call",
        where: m.status == "pending"

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      message ->
        message
        |> DisplayMessage.changeset(%{"status" => "executing"})
        |> Repo.update()
    end
  end

  def complete_tool_call(call_id, result_metadata \\ %{}) do
    query =
      from m in DisplayMessage,
        where: fragment("json_extract(?, '$.call_id') = ?", m.content, ^call_id),
        where: m.content_type == "tool_call",
        where: m.status in ["pending", "executing"]

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      message ->
        updated_metadata = Map.merge(message.metadata, result_metadata)

        message
        |> DisplayMessage.changeset(%{"status" => "completed", "metadata" => updated_metadata})
        |> Repo.update()
    end
  end

  def fail_tool_call(call_id, error_info \\ %{}) do
    query =
      from m in DisplayMessage,
        where: fragment("json_extract(?, '$.call_id') = ?", m.content, ^call_id),
        where: m.content_type == "tool_call",
        where: m.status in ["pending", "executing"]

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      message ->
        updated_metadata = Map.merge(message.metadata, error_info)

        message
        |> DisplayMessage.changeset(%{"status" => "failed", "metadata" => updated_metadata})
        |> Repo.update()
    end
  end

  def get_history(conversation_id, opts \\ []) do
    max_messages = Keyword.get(opts, :max_messages, 50)

    conversation_id
    |> load_display_messages(limit: max_messages * 2)
    |> Enum.reject(fn msg -> msg.content_type in ["notification", "thinking"] end)
    |> Enum.map(fn msg ->
      %{role: msg.message_type, content: DisplayMessage.to_text(msg)}
    end)
    |> Enum.reject(fn msg -> msg.content == "" end)
    |> Enum.take(-max_messages)
  end

  @doc false
  def welcome_message, do: @welcome_message

  defp create_welcome_message(conversation) do
    append_text_message(conversation.id, "system", @welcome_message)
  end

  defp now_utc, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
