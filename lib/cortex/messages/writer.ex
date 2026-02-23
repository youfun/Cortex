defmodule Cortex.Messages.Writer do
  @moduledoc """
  Centralized message writer.

  All channels emit signals; this process performs the single write to DB
  and re-emits a normalized message.created signal for UI consumers.
  """

  use GenServer
  require Logger

  alias Cortex.Conversations
  alias Cortex.SignalCatalog
  alias Cortex.SignalHub

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    SignalHub.subscribe("user.input.chat")
    SignalHub.subscribe(SignalCatalog.agent_response())
    SignalHub.subscribe(SignalCatalog.tool_call_request())
    SignalHub.subscribe(SignalCatalog.tool_call_result())
    SignalHub.subscribe("tool.result.**")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:signal, %Jido.Signal{type: "user.input.chat"} = signal}, state) do
    maybe_write_message(signal, "user")

    {:noreply, state}
  end

  def handle_info({:signal, %Jido.Signal{type: "agent.response"} = signal}, state) do
    maybe_write_message(signal, "assistant", fn payload ->
      %{metadata: %{model_name: payload[:model_name] || payload["model_name"]}}
    end)

    {:noreply, state}
  end

  def handle_info({:signal, %Jido.Signal{type: "tool.call.request"} = signal}, state) do
    maybe_write_tool_call_request(signal)

    {:noreply, state}
  end

  def handle_info({:signal, %Jido.Signal{type: "tool.call.result"} = signal}, state) do
    maybe_write_tool_result(signal)

    {:noreply, state}
  end

  def handle_info({:signal, %Jido.Signal{type: "tool.result." <> _} = signal}, state) do
    maybe_write_tool_result(signal)

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp maybe_write_message(%Jido.Signal{} = signal, role, extra_fun \\ fn _payload -> %{} end)
       when is_binary(role) and is_function(extra_fun, 1) do
    data = signal.data || %{}
    payload = signal_payload(data)

    with conversation_id when is_binary(conversation_id) <- conversation_id_from_payload(payload),
         content when is_binary(content) <- content_from_payload(payload),
         true <- content != "" do
      attrs =
        base_attrs(role, content, signal, data)
        |> merge_metadata(extra_fun.(payload))

      create_and_emit_message(attrs, conversation_id, data)
    end
  end

  # Removed unused functions: maybe_write_tool_calls, maybe_mark_tool_executing, tool_call_name, tool_call_args

  defp maybe_write_tool_call_request(%Jido.Signal{} = signal) do
    data = signal.data || %{}
    payload = signal_payload(data)

    with conversation_id when is_binary(conversation_id) <- conversation_id_from_payload(payload),
         call_id when is_binary(call_id) <- payload[:call_id] || payload["call_id"] do
      tool_name =
        payload[:tool] || payload["tool"] || payload[:tool_name] || payload["tool_name"] || "tool"

      arguments =
        payload[:params] || payload["params"] || payload[:arguments] || payload["arguments"] ||
          %{}

      case run_db(fn ->
             Conversations.append_tool_call_message(
               conversation_id,
               call_id,
               tool_name,
               arguments
             )
           end) do
        {:ok, {:ok, message}} -> emit_message_created(message, data)
        {:ok, {:error, _}} -> :ok
        {:error, _} -> :ok
      end
    end
  end

  defp maybe_write_tool_result(%Jido.Signal{} = signal) do
    data = signal.data || %{}
    payload = signal_payload(data)

    with conversation_id when is_binary(conversation_id) <- conversation_id_from_payload(payload),
         call_id when is_binary(call_id) <- payload[:call_id] || payload["call_id"] do
      result = Map.get(payload, :result, Map.get(payload, "result"))
      result_content = result_to_string(result)

      {tool_name, status_result} =
        case run_db(fn ->
               Conversations.complete_tool_call(call_id, %{"result" => result_content})
             end) do
          {:ok, {:ok, message}} -> {message.content["name"], {:ok, message}}
          {:ok, error} -> {payload[:tool_name] || payload["tool_name"] || "tool", error}
          {:error, _} -> {payload[:tool_name] || payload["tool_name"] || "tool", {:error, :db}}
        end

      case status_result do
        {:ok, message} -> emit_message_updated(message, data)
        _ -> :ok
      end

      case run_db(fn ->
             Conversations.append_tool_result_message(
               conversation_id,
               call_id,
               tool_name || "tool",
               result_content,
               false
             )
           end) do
        {:ok, {:ok, message}} -> emit_message_created(message, data)
        {:ok, {:error, _}} -> :ok
        {:error, _} -> :ok
      end
    end
  end

  defp conversation_id_from_payload(payload) when is_map(payload) do
    conversation_id =
      case first_present(payload, [:conversation_id, "conversation_id"]) do
        nil ->
          payload
          |> first_present([:session_id, "session_id"])
          |> session_to_conversation()

        id ->
          id
      end

    if is_binary(conversation_id) do
      case run_db(fn -> Conversations.get_conversation(conversation_id) end) do
        {:ok, %{} = _conversation} -> conversation_id
        {:ok, nil} -> nil
        {:error, _} -> nil
      end
    else
      nil
    end
  end

  defp conversation_id_from_payload(_payload), do: nil

  defp content_from_payload(payload) when is_map(payload) do
    first_present(payload, [:content, "content"])
  end

  defp content_from_payload(_payload), do: nil

  defp first_present(payload, keys) when is_map(payload) and is_list(keys) do
    Enum.find_value(keys, fn key -> Map.get(payload, key) end)
  end

  defp base_attrs(role, content, %Jido.Signal{} = signal, data) do
    %{
      message_type: role,
      content_type: "text",
      content: %{"text" => content},
      metadata: %{
        signal_id: signal.id,
        origin: data[:origin] || data["origin"],
        channel: data[:provider] || data["provider"]
      }
    }
  end

  defp create_and_emit_message(attrs, conversation_id, data) do
    case run_db(fn -> Conversations.append_display_message(conversation_id, attrs) end) do
      {:ok, {:ok, message}} ->
        emit_message_created(message, data)

      {:ok, {:error, %Ecto.Changeset{} = changeset}} ->
        Logger.error("[Messages.Writer] Message insert failed: #{inspect(changeset)}")

      {:ok, {:error, reason}} ->
        Logger.error("[Messages.Writer] Message insert failed: #{inspect(reason)}")

      {:error, _} ->
        :ok
    end
  end

  defp emit_message_created(message, data) do
    origin = normalize_origin(data[:origin] || data["origin"])

    SignalHub.emit(
      "conversation.message.created",
      %{
        provider: "system",
        event: "message",
        action: "create",
        actor: "message_writer",
        origin: origin,
        session_id: message.conversation_id,
        message: message_payload(message)
      },
      source: "/messages/writer"
    )
  end

  defp emit_message_updated(message, data) do
    origin = normalize_origin(data[:origin] || data["origin"])

    SignalHub.emit(
      "conversation.message.updated",
      %{
        provider: "system",
        event: "message",
        action: "update",
        actor: "message_writer",
        origin: origin,
        session_id: message.conversation_id,
        message: message_payload(message)
      },
      source: "/messages/writer"
    )
  end

  defp message_payload(message) do
    %{
      id: message.id,
      message_type: message.message_type,
      content_type: message.content_type,
      content: message.content,
      status: message.status,
      metadata: message.metadata,
      sequence: message.sequence,
      inserted_at: message.inserted_at
    }
  end

  defp normalize_origin(origin) when is_map(origin) do
    origin
    |> Map.put_new(:channel, "system")
    |> Map.put_new(:client, "message_writer")
    |> Map.put_new(:platform, "server")
  end

  defp normalize_origin(_), do: %{channel: "system", client: "message_writer", platform: "server"}

  defp session_to_conversation(nil), do: nil

  defp session_to_conversation("session_" <> rest), do: rest

  defp session_to_conversation(session_id), do: session_id

  defp signal_payload(data) when is_map(data) do
    payload = Map.get(data, :payload) || Map.get(data, "payload")

    if is_map(payload) and map_size(payload) > 0 do
      payload
    else
      data
    end
  end

  defp result_to_string(result) do
    cond do
      is_binary(result) -> result
      is_map(result) and is_binary(Map.get(result, :output)) -> Map.get(result, :output)
      is_map(result) and is_binary(Map.get(result, "output")) -> Map.get(result, "output")
      true -> inspect(result)
    end
  end

  defp merge_metadata(attrs, extra) do
    metadata = Map.merge(Map.get(attrs, :metadata, %{}), Map.get(extra, :metadata, %{}))

    attrs
    |> Map.merge(Map.delete(extra, :metadata))
    |> Map.put(:metadata, metadata)
  end

  defp run_db(fun) when is_function(fun, 0) do
    try do
      {:ok, fun.()}
    rescue
      e in [
        DBConnection.OwnershipError,
        DBConnection.ConnectionError,
        Exqlite.Error,
        Ecto.StaleEntryError,
        Ecto.ConstraintError
      ] ->
        Logger.debug("[Messages.Writer] DB unavailable: #{Exception.message(e)}")
        {:error, e}
    catch
      :exit, reason ->
        Logger.debug("[Messages.Writer] DB exit: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
