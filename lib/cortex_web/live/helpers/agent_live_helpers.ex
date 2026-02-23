defmodule CortexWeb.AgentLiveHelpers do
  @moduledoc """
  Agent-related LiveView helpers extracted from JidoLive.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [stream: 4, stream_insert: 3]

  alias Cortex.Config.{Metadata, ModelSelector, Settings}
  alias Cortex.Conversations
  alias Cortex.Session.Coordinator

  require Logger

  def init_agent_state(socket, conversation, session_id) do
    socket
    |> assign(:session_id, session_id)
    |> assign(:current_conversation_id, conversation.id)
    |> assign(:is_thinking, false)
    |> assign(:plan_stream_text, "")
    |> assign(:plan_thought_text, "")
    |> assign(:plan_thought_visible, false)
    |> assign(:plan_tool_calls, [])
    |> assign(:plan_todo_entries, [])
    |> assign(:pending_context, nil)
    |> assign(:current_request_id, nil)
    |> assign(:current_agent_id, nil)
    |> assign(:native_result_handled, false)
    |> assign(:pending_tool_calls_count, 0)
    |> assign(:last_summary_hash, nil)
    |> assign(:streaming_messages, %{})
    |> assign(:show_permission_modal, false)
    |> assign(:pending_permission_request, nil)
    |> assign(:permission_queue, [])
  end

  def resolve_model(conversation) do
    model_config = conversation.model_config || %{}

    case ModelSelector.default_model_info() do
      {:ok, {default_model_name, default_model_id}} ->
        case ModelSelector.resolve_model_from_config(
               model_config,
               default_model_name,
               default_model_id
             ) do
          {:ok, {model_name, model_id}} -> {model_name, model_id, nil}
          {:error, :no_available_models} -> {nil, nil, no_available_models_error()}
        end

      {:error, :no_available_models} ->
        {nil, nil, no_available_models_error()}
    end
  end

  def list_available_models do
    Metadata.get_available_models()
    |> Enum.map(fn m ->
      %{id: m.id, name: m.display_name || m.name, provider: m.provider_drive, model_name: m.name}
    end)
  end

  def base_messages(conversation) do
    conversation.id
    |> Conversations.load_display_messages()
    |> Enum.map(&to_message_map/1)
  end

  def maybe_append_model_error(messages, nil), do: messages

  def maybe_append_model_error(messages, model_error) when is_binary(model_error) do
    messages ++
      [
        %{
          id: ui_message_id(),
          message_type: "system",
          content_type: "notification",
          content: %{"text" => model_error},
          status: "completed",
          model_name: nil,
          inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }
      ]
  end

  def switch_to_conversation(socket, conversation_id) do
    old_conversation_id = socket.assigns.current_conversation_id
    conversation = Conversations.get_conversation!(conversation_id)
    _ = Conversations.touch_conversation(conversation)

    new_session_id = Coordinator.session_id(conversation.id)
    messages = load_conversation_messages(conversation_id)
    conversations = Conversations.list_conversations(socket.assigns.workspace.id)
    {restored_model_name, restored_model_id, model_error} = resolve_model(conversation)

    emit_conversation_switch(socket, conversation_id, new_session_id)

    if restored_model_name do
      emit_model_change(socket, restored_model_name, new_session_id)
    else
      Logger.error("JidoLive: No available models configured")
    end

    messages = maybe_append_model_error(messages, model_error)

    socket =
      socket
      |> assign(
        current_conversation_id: conversation_id,
        session_id: new_session_id,
        selected_model_id: restored_model_id,
        is_thinking: false,
        pending_tool_calls_count: 0,
        streaming_messages: %{},
        plan_stream_text: "",
        plan_thought_text: ""
      )
      |> stream(:conversations, conversations, reset: true)
      |> stream(:messages, messages, reset: true)

    Coordinator.switch_session(
      old_conversation_id,
      conversation_id,
      model: restored_model_name || get_current_model_name(socket),
      workspace_id: socket.assigns.workspace.id
    )

    socket
  end

  def reset_to_conversation(socket, conversation_id, workspace_id) do
    messages = load_conversation_messages(conversation_id)
    new_session_id = Coordinator.session_id(conversation_id)
    conversations = Conversations.list_conversations(workspace_id)

    socket
    |> assign(
      current_conversation_id: conversation_id,
      session_id: new_session_id,
      is_thinking: false,
      streaming_messages: %{}
    )
    |> stream(:conversations, conversations, reset: true)
    |> stream(:messages, messages, reset: true)
  end

  def new_conversation(socket) do
    workspace_id = socket.assigns.workspace.id
    normalized_agent_id = normalize_agent_id(socket.assigns.selected_agent_id)

    {:ok, new_conv} =
      Conversations.create_conversation(
        %{
          title: new_conversation_title(),
          model_config: %{
            model_id: socket.assigns.selected_model_id,
            agent_id: normalized_agent_id
          }
        },
        workspace_id
      )

    new_session_id = Coordinator.session_id(new_conv.id)
    emit_conversation_switch(socket, new_conv.id, new_session_id)

    socket =
      socket
      |> assign(
        current_conversation_id: new_conv.id,
        session_id: new_session_id,
        is_thinking: false,
        streaming_messages: %{},
        plan_stream_text: "",
        plan_thought_text: ""
      )
      |> stream(:conversations, Conversations.list_conversations(workspace_id), reset: true)
      |> stream(:messages, [], reset: true)

    Coordinator.ensure_session(new_conv.id,
      model: get_current_model_name(socket),
      workspace_id: workspace_id
    )

    socket
  end

  def delete_conversation(socket, id) do
    conversation = Conversations.get_conversation!(id)

    if id == socket.assigns.current_conversation_id and socket.assigns.is_thinking do
      emit_cancel(socket)
    end

    {:ok, _} = Conversations.delete_conversation(conversation)
    _ = Coordinator.stop_session(id)

    workspace_id = socket.assigns.workspace.id
    conversations = Conversations.list_conversations(workspace_id)

    {current_id, messages} =
      cond do
        id != socket.assigns.current_conversation_id ->
          msgs = load_conversation_messages(socket.assigns.current_conversation_id)
          {socket.assigns.current_conversation_id, msgs}

        conversations != [] ->
          first = List.first(conversations)
          msgs = load_conversation_messages(first.id)
          {first.id, msgs}

        true ->
          {:ok, new_conv} =
            Conversations.create_conversation(%{title: new_conversation_title()}, workspace_id)

          {new_conv.id, []}
      end

    new_session_id = Coordinator.session_id(current_id)

    socket =
      socket
      |> assign(
        current_conversation_id: current_id,
        session_id: new_session_id,
        is_thinking: false
      )
      |> stream(:conversations, conversations, reset: true)
      |> stream(:messages, messages, reset: true)

    Coordinator.ensure_session(current_id,
      model: get_current_model_name(socket),
      workspace_id: workspace_id
    )

    socket
  end

  def archive_conversation(socket, id) do
    conversation = Conversations.get_conversation!(id)

    if id == socket.assigns.current_conversation_id and socket.assigns.is_thinking do
      emit_cancel(socket)
    end

    {:ok, _} = Conversations.archive_conversation(conversation)

    workspace_id = socket.assigns.workspace.id
    conversations = Conversations.list_conversations(workspace_id)
    archived_count = Conversations.count_archived(workspace_id)

    {current_id, messages} =
      cond do
        id != socket.assigns.current_conversation_id ->
          msgs = load_conversation_messages(socket.assigns.current_conversation_id)
          {socket.assigns.current_conversation_id, msgs}

        conversations != [] ->
          first = List.first(conversations)
          msgs = load_conversation_messages(first.id)
          {first.id, msgs}

        true ->
          {:ok, new_conv} =
            Conversations.create_conversation(%{title: new_conversation_title()}, workspace_id)

          {new_conv.id, []}
      end

    socket
    |> assign(
      current_conversation_id: current_id,
      archived_count: archived_count,
      is_thinking: false
    )
    |> stream(:conversations, conversations, reset: true)
    |> stream(:messages, messages, reset: true)
  end

  def select_model(socket, model_id) do
    model = Enum.find(socket.assigns.models, &(&1.id == model_id))

    if model do
      Logger.debug("JidoLive: User selected model #{model.model_name}")
      Settings.set_skill_default_model(model.model_name)
      emit_model_change(socket, model.model_name, socket.assigns.session_id)
    end

    assign(socket, 
      selected_model_id: model_id, 
      selected_model: model,
      show_model_selector: false
    )
  end

  def select_agent(socket, agent_id) do
    normalized_id = normalize_agent_id(agent_id)
    assign(socket, selected_agent_id: normalized_id, show_agent_selector: false)
  end

  def send_message(socket, content) do
    trimmed_content = String.trim(content)
    has_context = not is_nil(socket.assigns.pending_context)

    cond do
      missing_model_config?(socket) ->
        stream_ui_message(socket, %{content: no_available_models_error()})

      trimmed_content == "" and not has_context ->
        socket

      true ->
        final_content = default_message_if_blank(trimmed_content, has_context)

        log_send_message(socket, final_content, has_context)
        emit_user_input_chat(socket, final_content)

        socket
        |> maybe_emit_pending_context()
        |> dispatch_chat_request(final_content)
        |> assign(is_thinking: true, pending_context: nil)
    end
  end

  def accumulate_stream_chunk(socket, message_id, chunk) do
    new_streaming =
      Map.update(
        socket.assigns.streaming_messages,
        message_id,
        %{
          id: message_id,
          message_type: "assistant",
          content_type: "text",
          content: %{"text" => chunk},
          status: "completed",
          inserted_at: DateTime.utc_now()
        },
        fn msg ->
          content = msg.content || %{}
          text = Map.get(content, "text", "") <> chunk
          %{msg | content: Map.put(content, "text", text)}
        end
      )

    assign(socket, streaming_messages: new_streaming)
  end

  def clear_streaming_state(socket) do
    assign(socket, is_thinking: false, streaming_messages: %{})
  end

  def handle_context_selected(path, socket) do
    expanded = Path.expand(path)

    cond do
      File.regular?(expanded) -> handle_file_context(expanded, socket)
      File.dir?(expanded) -> handle_dir_context(expanded, socket)
      true -> {:noreply, socket}
    end
  end

  def handle_folder_selected(path, socket) do
    handle_dir_context(path, socket)
  end

  def create_and_stream_message(socket, attrs) do
    message = build_ui_message(attrs)
    {:ok, stream_insert(socket, :messages, message)}
  end

  def stream_ui_message(socket, attrs) do
    message =
      attrs
      |> Map.put_new(:message_type, "system")
      |> Map.put_new(:content_type, "notification")
      |> Map.put_new(:content, "")
      |> build_ui_message()

    stream_insert(socket, :messages, message)
  end

  def emit_permission_resolve(socket, request_id, decision) do
    approved = decision in [:allow, :allow_always, "allow", "allow_always"]

    Cortex.SignalHub.emit(
      "permission.resolved",
      %{
        provider: "ui",
        event: "permission",
        action: "resolve",
        actor: "user",
        origin: get_origin(socket),
        request_id: request_id,
        decision: decision,
        approved: approved,
        session_id: socket.assigns.session_id
      },
      source: "/ui/web/permission"
    )
  end

  def emit_conversation_switch(socket, conversation_id, session_id) do
    history = Conversations.get_history(conversation_id)

    Cortex.SignalHub.emit(
      "agent.conversation.switch",
      %{
        provider: "ui",
        event: "conversation",
        action: "switch",
        actor: "user",
        origin: get_origin(socket) |> Map.put(:session_id, session_id),
        conversation_id: conversation_id,
        history: history,
        session_id: session_id
      },
      source: "/ui/web/conversation"
    )
  end

  def emit_model_change(socket, model_name, session_id) do
    Cortex.SignalHub.emit(
      "agent.model.change",
      %{
        provider: "ui",
        event: "model",
        action: "change",
        actor: "user",
        origin: get_origin(socket) |> Map.put(:session_id, session_id),
        model_name: model_name,
        session_id: session_id
      },
      source: "/ui/web/settings"
    )
  end

  def emit_cancel(socket) do
    Cortex.SignalHub.emit(
      "agent.cancel",
      %{
        provider: "ui",
        event: "agent",
        action: "cancel",
        actor: "user",
        origin: get_origin(socket),
        session_id: socket.assigns.session_id
      },
      source: "/ui/web/conversation"
    )
  end

  def ui_message_id do
    "ui_" <> Integer.to_string(System.unique_integer([:positive]))
  end

  def get_origin(socket) do
    %{
      channel: "ui",
      client: "web",
      platform: "windows",
      user_id_hash: "u_default",
      session_id: socket.assigns.session_id
    }
  end

  def get_current_model_name(socket) do
    case Enum.find(socket.assigns.models, &(&1.id == socket.assigns.selected_model_id)) do
      nil -> "unknown"
      model -> model.model_name
    end
  end

  def normalize_agent_id(nil), do: nil
  def normalize_agent_id(""), do: nil
  def normalize_agent_id("nil"), do: nil
  def normalize_agent_id(agent_id), do: agent_id

  def new_conversation_title do
    "New Chat #{Calendar.strftime(DateTime.utc_now(), "%H:%M")}"
  end

  def signal_payload(%Jido.Signal{data: data}) when is_map(data) do
    payload = Map.get(data, :payload) || Map.get(data, "payload")

    if is_map(payload) and map_size(payload) > 0 do
      payload
    else
      data
    end
  end

  def belongs_to_session?(signal, socket) do
    payload = signal_payload(signal)

    session_id =
      payload[:session_id] ||
        payload["session_id"] ||
        payload[:conversation_id] ||
        payload["conversation_id"] ||
        get_in(signal.data, [:origin, :session_id]) ||
        get_in(signal.data, ["origin", "session_id"]) ||
        get_in(signal.data, [:origin, :conversation_id]) ||
        get_in(signal.data, ["origin", "conversation_id"])

    session_id in [
      socket.assigns.current_conversation_id,
      socket.assigns.session_id
    ]
  end

  def file_context_message(relative, content) do
    %{
      role: "system",
      content: "Please refer to the following file content:\n\n📄 File: `#{relative}`\n```\n#{content}\n```"
    }
  end

  defp no_available_models_error do
    "No available models found. Please configure and enable models in settings first."
  end

  defp load_conversation_messages(conversation_id) do
    conversation_id
    |> Conversations.load_display_messages()
    |> Enum.map(&to_message_map/1)
  end

  defp to_message_map(%Cortex.Conversations.DisplayMessage{} = msg) do
    %{
      id: msg.id,
      message_type: msg.message_type,
      content_type: msg.content_type,
      content: msg.content,
      status: msg.status,
      metadata: msg.metadata,
      sequence: msg.sequence,
      inserted_at: msg.inserted_at
    }
  end

  defp to_message_map(map) when is_map(map), do: map

  defp missing_model_config?(socket) do
    socket.assigns.selected_model_id in [nil, ""] or socket.assigns.models == []
  end

  defp default_message_if_blank("", true), do: "Please analyze based on the provided context"
  defp default_message_if_blank(content, _has_context), do: content

  defp log_send_message(socket, final_content, has_context) do
    Logger.debug("===== JidoLive: SEND_MESSAGE EVENT =====")
    Logger.debug("JidoLive: Final content: '#{final_content}'")
    Logger.debug("JidoLive: Context exists: #{has_context}")
    Logger.debug("JidoLive: Session ID: #{socket.assigns.session_id}")
    Logger.debug("JidoLive: Conversation ID: #{socket.assigns.current_conversation_id}")
    Logger.debug("JidoLive: Selected agent ID: #{inspect(socket.assigns.selected_agent_id)}")
  end

  defp emit_user_input_chat(socket, final_content) do
    Cortex.SignalHub.emit(
      "user.input.chat",
      %{
        provider: "ui",
        event: "chat",
        action: "input",
        actor: "user",
        origin: get_origin(socket),
        content: final_content,
        session_id: socket.assigns.session_id,
        conversation_id: socket.assigns.current_conversation_id
      },
      source: "/ui/web/chat"
    )
  end

  defp maybe_emit_pending_context(%{assigns: %{pending_context: nil}} = socket), do: socket

  defp maybe_emit_pending_context(socket) do
    Logger.debug("JidoLive: pending_context = #{inspect(socket.assigns.pending_context)}")
    Logger.info("📋 Processing pending_context: #{inspect(socket.assigns.pending_context)}")

    emit_pending_context(socket, socket.assigns.pending_context)
    socket
  end

  defp emit_pending_context(socket, %{type: :file, path: path}) do
    Logger.info("🔍 Attempting to read file: #{path}")

    case File.read(path) do
      {:ok, content} ->
        relative = Path.relative_to_cwd(path)
        context_msg = file_context_message(relative, content)

        Logger.debug(
          "JidoLive: Adding file context to LLM, content length: #{String.length(content)}"
        )

        emit_context_add(socket, context_msg, "/ui/context")
        Logger.debug("JidoLive: Context added successfully")

      {:error, reason} ->
        Logger.warning("❌ Failed to read file context: #{inspect(reason)}")
    end
  end

  defp emit_pending_context(socket, %{type: :directory, content: dir_context}) do
    emit_context_add(socket, %{role: "user", content: dir_context}, "/ui/web/context")
  end

  defp emit_pending_context(socket, context_msg) do
    emit_context_add(socket, context_msg, "/ui/web/context")
  end

  defp emit_context_add(socket, context_msg, source) do
    Cortex.SignalHub.emit(
      "agent.context.add",
      %{
        provider: "ui",
        event: "context",
        action: "add",
        actor: "user",
        origin: get_origin(socket),
        message: context_msg,
        session_id: socket.assigns.session_id
      },
      source: source
    )
  end

  defp dispatch_chat_request(socket, final_content) do
    Logger.debug("JidoLive: Emitting agent.chat.request signal")

    Cortex.SignalHub.emit(
      "agent.chat.request",
      %{
        provider: "ui",
        event: "chat",
        action: "request",
        actor: "user",
        origin: get_origin(socket),
        content: final_content,
        model: get_current_model_name(socket),
        session_id: socket.assigns.session_id,
        conversation_id: socket.assigns.current_conversation_id
      },
      source: "/ui/web/chat"
    )

    socket
  end

  defp build_ui_message(attrs) do
    {content_type, content} = normalize_content(attrs)

    attrs
    |> Map.put(:content_type, content_type)
    |> Map.put(:content, content)
    |> Map.put_new(:status, "completed")
    |> Map.put_new(:id, ui_message_id())
    |> Map.put_new(:inserted_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> Map.put_new(:model_name, nil)
  end

  defp normalize_content(attrs) do
    content = Map.get(attrs, :content)
    content_type = Map.get(attrs, :content_type, "text")

    cond do
      is_map(content) -> {content_type, content}
      is_binary(content) -> {content_type, %{"text" => content}}
      true -> {content_type, %{"text" => ""}}
    end
  end

  defp handle_file_context(path, socket) do
    relative = Path.relative_to_cwd(path)

    if socket.assigns.show_add_folder_modal do
      ui_msg = %{
        content: "📎 File selected: `#{relative}`\nFile content will be automatically read when sending message."
      }

      pending = %{type: :file, path: path}

      socket =
        socket
        |> assign(
          show_add_folder_modal: false,
          pending_context: pending
        )
        |> stream_ui_message(ui_msg)

      {:noreply, socket}
    else
      ui_msg = %{
        content: "📎 File selected: `#{relative}`\nFile content will be automatically read when sending message."
      }

      pending = %{type: :file, path: path}

      socket =
        socket
        |> assign(pending_context: pending)
        |> stream_ui_message(ui_msg)

      {:noreply, socket}
    end
  end

  defp handle_dir_context(path, socket) do
    dir_name = Path.relative_to_cwd(path)

    case File.ls(path) do
      {:ok, files} ->
        visible_files = Enum.filter(files, fn f -> !String.starts_with?(f, ".") end)
        file_list = Enum.map_join(visible_files, "\n", fn f -> "- #{f}" end)

        full_path_list =
          Enum.map_join(visible_files, "\n", fn f -> "- #{Path.join(dir_name, f)}" end)

        ui_msg = %{
          content:
            "📎 Directory selected: `#{dir_name}` (contains #{length(visible_files)} files)\nFile list will be included when sending message.\nFile list:\n#{file_list}"
        }

        llm_context_content = """
        📂 Current context folder: `#{dir_name}`
        Included file list (please use full relative paths to access):
        #{full_path_list}
        """

        pending = %{type: :directory, content: llm_context_content, path: path}

        socket =
          socket
          |> assign(
            show_add_folder_modal: false,
            pending_context: pending
          )
          |> stream_ui_message(ui_msg)

        {:noreply, socket}

      {:error, reason} ->
        err_msg = %{content: "Unable to read folder: #{inspect(reason)}"}

        socket =
          socket
          |> assign(show_add_folder_modal: false)
          |> stream_ui_message(err_msg)

        {:noreply, socket}
    end
  end

end
