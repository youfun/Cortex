defmodule CortexWeb.JidoLive do
  use CortexWeb, :live_view
  on_mount CortexWeb.Hooks.SignalSubscriber
  require Logger

  alias Cortex.{Conversations, Workspaces}
  alias Cortex.Session.Coordinator
  alias CortexWeb.AgentLiveHelpers
  alias CortexWeb.PermissionHelpers
  alias CortexWeb.SignalDispatcher
  import CortexWeb.JidoComponents

  @impl true
  def mount(_params, _session, socket) do
    {workspace, conversations, current_conversation} = init_workspace_conversation()
    session_id = Coordinator.session_id(current_conversation.id)
    available_models = AgentLiveHelpers.list_available_models()

    {initial_model_name, initial_model_id, model_error} =
      AgentLiveHelpers.resolve_model(current_conversation)

    {:ok, _session} =
      Coordinator.ensure_session(current_conversation.id,
        model: initial_model_name,
        workspace_id: workspace.id
      )

    messages =
      current_conversation
      |> AgentLiveHelpers.base_messages()
      |> AgentLiveHelpers.maybe_append_model_error(model_error)

    socket =
      assign(socket,
        active_tab: :chat,
        active_panel: "chat",
        workspace: workspace,
        archived_count: Conversations.count_archived(workspace.id),
        show_model_selector: false,
        show_agent_selector: false,
        active_session: %{title: "Getting Started with Jido"},
        plan_mode_status: "idle",
        plan_mode_progress: nil,
        current_plan_id: nil,
        messages: messages,
        agents: [],
        models: available_models,
        selected_model_id: initial_model_id,
        selected_agent_id: nil,
        settings: %{
          appearance: %{theme: "dark", font_size: 14},
          network: %{proxy_enabled: false, proxy_url: "http://127.0.0.1:7890"}
        },
        show_add_folder_modal: false,
        new_folder_path: "",
        # Authorization Management
        show_auth_management: false,
        authorized_paths: restore_authorized_folders(current_conversation, session_id),
        authorized_paths_with_mode: [],
        # Archived Conversations
        show_archived_modal: false,
        archived_conversations: []
      )
      |> AgentLiveHelpers.init_agent_state(current_conversation, session_id)
      |> stream(:conversations, conversations)
      |> stream(:messages, messages)
      |> maybe_notify_loaded_skills()

    {:ok, socket}
  end

  defp init_workspace_conversation do
    workspace = Workspaces.ensure_default_workspace()
    conversations = Conversations.list_conversations(workspace.id)
    current_conversation = ensure_current_conversation(conversations, workspace.id)
    {workspace, conversations, current_conversation}
  end

  defp ensure_current_conversation([first | _], _workspace_id) do
    {:ok, touched} = Conversations.touch_conversation(first)
    touched
  end

  defp ensure_current_conversation([], workspace_id) do
    {:ok, conversation} =
      Conversations.create_conversation(
        %{title: AgentLiveHelpers.new_conversation_title()},
        workspace_id
      )

    conversation
  end

  defp maybe_notify_loaded_skills(socket) do
    if connected?(socket), do: send(self(), :notify_loaded_skills)
    socket
  end

  # ============================================================================
  # Event Handlers (UI Interactions)
  # ============================================================================

  @impl true
  def handle_event("setActivePanel", %{"panel" => panel}, socket) do
    {:noreply, assign(socket, active_panel: panel)}
  end

  def handle_event("toggle_model_selector", _params, socket) do
    {:noreply, assign(socket, show_model_selector: !socket.assigns.show_model_selector)}
  end

  def handle_event("toggle_agent_selector", _params, socket) do
    {:noreply, assign(socket, show_agent_selector: !socket.assigns.show_agent_selector)}
  end

  def handle_event("select_model", %{"id" => model_id}, socket) do
    {:noreply, AgentLiveHelpers.select_model(socket, model_id)}
  end

  def handle_event("select_agent", %{"id" => agent_id}, socket) do
    {:noreply, AgentLiveHelpers.select_agent(socket, agent_id)}
  end

  def handle_event("new_conversation", _, socket) do
    socket = AgentLiveHelpers.new_conversation(socket)
    send(self(), :notify_loaded_skills)
    {:noreply, socket}
  end

  def handle_event("switch_conversation", %{"id" => id}, socket) do
    {:noreply, AgentLiveHelpers.switch_to_conversation(socket, id)}
  end

  def handle_event("delete_conversation", %{"id" => id}, socket) do
    {:noreply, AgentLiveHelpers.delete_conversation(socket, id)}
  end

  def handle_event("show_archived", _params, socket) do
    workspace_id = socket.assigns.workspace.id
    archived = Conversations.list_archived_conversations(workspace_id)

    {:noreply, assign(socket, show_archived_modal: true, archived_conversations: archived)}
  end

  def handle_event("close_archived_modal", _params, socket) do
    {:noreply, assign(socket, show_archived_modal: false)}
  end

  def handle_event("archive_conversation", %{"id" => id}, socket) do
    {:noreply, AgentLiveHelpers.archive_conversation(socket, id)}
  end

  def handle_event("restore_conversation", %{"id" => id}, socket) do
    conversation = Conversations.get_conversation!(id)
    {:ok, _} = Conversations.restore_conversation(conversation)

    workspace_id = socket.assigns.workspace.id
    archived = Conversations.list_archived_conversations(workspace_id)
    archived_count = Conversations.count_archived(workspace_id)

    socket =
      socket
      |> assign(archived_conversations: archived, archived_count: archived_count)
      |> stream(:conversations, Conversations.list_conversations(workspace_id), reset: true)

    {:noreply, socket}
  end

  def handle_event("delete_archived_conversation", %{"id" => id}, socket) do
    conversation = Conversations.get_conversation!(id)
    {:ok, _} = Conversations.delete_conversation(conversation)

    workspace_id = socket.assigns.workspace.id
    archived = Conversations.list_archived_conversations(workspace_id)
    archived_count = Conversations.count_archived(workspace_id)

    {:noreply, assign(socket, archived_conversations: archived, archived_count: archived_count)}
  end

  def handle_event("send_message", %{"message" => content}, socket) do
    {:noreply, AgentLiveHelpers.send_message(socket, content)}
  end

  def handle_event("resolve_permission", %{"request_id" => id, "decision" => dec}, socket) do
    AgentLiveHelpers.emit_permission_resolve(socket, id, PermissionHelpers.parse_decision(dec))
    {:noreply, assign(socket, show_permission_modal: false)}
  end

  def handle_event("approve_permission", _, socket) do
    req = socket.assigns.pending_permission_request
    {:noreply, PermissionHelpers.resolve(socket, req.request_id, :allow)}
  end

  def handle_event("reject_permission", _, socket) do
    req = socket.assigns.pending_permission_request
    {:noreply, PermissionHelpers.resolve(socket, req.request_id, :deny)}
  end

  def handle_event("approve_permission_always", _, socket) do
    req = socket.assigns.pending_permission_request
    {:noreply, PermissionHelpers.resolve(socket, req.request_id, :allow_always)}
  end

  def handle_event("close_permission_modal", _, socket) do
    socket =
      case socket.assigns.pending_permission_request do
        nil -> PermissionHelpers.consume_queue(socket)
        req -> PermissionHelpers.resolve(socket, req.request_id, :deny)
      end

    {:noreply, socket}
  end

  def handle_event("open_add_folder_modal", _, socket) do
    {:noreply,
     assign(socket,
       show_add_folder_modal: true,
       new_folder_path: Cortex.Workspaces.ensure_workspace_root!()
     )}
  end

  def handle_event("close_add_folder_modal", _, socket) do
    {:noreply, assign(socket, show_add_folder_modal: false)}
  end

  def handle_event("remove_authorized_folder", %{"path" => path}, socket) do
    agent_id = socket.assigns.session_id
    Cortex.Core.PermissionTracker.remove_authorized_folder(agent_id, path)
    folders = Cortex.Core.PermissionTracker.list_authorized_folders(agent_id)

    persist_authorized_folders(socket.assigns.current_conversation_id, folders)

    Cortex.SignalHub.emit(
      "permission.folder.remove",
      %{
        provider: "ui",
        event: "permission",
        action: "folder_remove",
        actor: "user",
        origin: %{channel: "ui", client: "web", platform: "browser"},
        agent_id: agent_id,
        folder_path: path
      },
      source: "/ui/web/permission"
    )

    {:noreply, assign(socket, authorized_paths: folders)}
  end

  def handle_event("shutdown", _, socket) do
    Task.start(fn ->
      Process.sleep(100)
      :init.stop()
    end)

    {:noreply, socket}
  end

  # ============================================================================
  # Info Handlers (Internal & PubSub Signals)
  # ============================================================================

  @impl true
  def handle_info({:signal, %Jido.Signal{type: type} = signal}, socket) do
    # 只有非 chunk 信号才打印详细日志，避免日志洪泛
    # 对于流式输出，只在开始时打印一次
    cond do
      type == "agent.response" ->
        payload = AgentLiveHelpers.signal_payload(signal)
        payload_session_id = payload[:session_id] || payload["session_id"]

        Logger.debug(
          "JidoLive: agent.response pid=#{inspect(self())} socket_session_id=#{socket.assigns.session_id} payload_session_id=#{inspect(payload_session_id)}"
        )

      type == "agent.response.chunk" ->
        payload = AgentLiveHelpers.signal_payload(signal)
        message_id = payload[:message_id] || payload["message_id"]

        unless Map.has_key?(socket.assigns.streaming_messages, message_id) do
          Logger.debug(
            "===== JidoLive: STREAMING STARTED (type: #{type}, id: #{message_id}) ====="
          )
        end

      type == "agent.think" ->
        # 思考过程也比较频繁，简化日志
        Logger.debug("===== JidoLive: AGENT THINKING =====")

      true ->
        Logger.debug("===== JidoLive: SIGNAL RECEIVED =====")
        Logger.debug("JidoLive: Signal type: #{type}")
        Logger.debug("JidoLive: Signal data: #{inspect(signal.data)}")
        Logger.debug("JidoLive: Signal source: #{inspect(signal.source)}")
    end

    socket = SignalDispatcher.dispatch(type, signal, socket)
    {:noreply, socket}
  end

  def handle_info(:notify_loaded_skills, socket) do
    {:ok, skills} =
      Cortex.Skills.Loader.load_all(Cortex.Workspaces.workspace_root(),
        emit_signals: false
      )

    count = length(skills)

    if count > 0 do
      max_names = 8
      names = skills |> Enum.map(& &1.name) |> Enum.take(max_names)
      suffix = if count > max_names, do: " ...", else: ""

      msg = %{
        id: AgentLiveHelpers.ui_message_id(),
        message_type: "system",
        content_type: "notification",
        content: %{
          "text" =>
            "✅ Loaded #{count} skills: " <>
              Enum.join(names, ", ") <> suffix
        },
        status: "completed",
        model_name: nil,
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      {:noreply, stream_insert(socket, :messages, msg)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:coordinator_delayed_stop, _conversation_id}, socket) do
    {:noreply, socket}
  end

  def handle_info({:user_message, content}, socket) do
    case AgentLiveHelpers.create_and_stream_message(socket, %{
           message_type: "user",
           content_type: "text",
           content: content
         }) do
      {:ok, updated} -> {:noreply, updated}
    end
  end

  # Removed legacy PubSub handle_info callbacks - now using dispatch_signal via SignalHub

  def handle_info({:context_selected, path}, socket) do
    expanded = Path.expand(path)

    if File.dir?(expanded) do
      handle_add_authorized_folder(expanded, socket)
    else
      AgentLiveHelpers.handle_context_selected(path, socket)
    end
  end

  def handle_info({:folder_selected, path}, socket) do
    handle_add_authorized_folder(Path.expand(path), socket)
  end

  defp handle_add_authorized_folder(expanded_path, socket) do
    workspace_root = Cortex.Workspaces.workspace_root()
    relative = Path.relative_to(expanded_path, workspace_root)
    agent_id = socket.assigns.session_id

    Cortex.Core.PermissionTracker.add_authorized_folder(agent_id, relative)
    folders = Cortex.Core.PermissionTracker.list_authorized_folders(agent_id)

    persist_authorized_folders(socket.assigns.current_conversation_id, folders)

    Cortex.SignalHub.emit(
      "permission.folder.add",
      %{
        provider: "ui",
        event: "permission",
        action: "folder_add",
        actor: "user",
        origin: %{channel: "ui", client: "web", platform: "browser"},
        agent_id: agent_id,
        folder_path: relative
      },
      source: "/ui/web/permission"
    )

    ui_msg = %{
      content: "Authorized folder: `#{relative}`"
    }

    socket =
      socket
      |> assign(show_add_folder_modal: false, authorized_paths: folders)
      |> AgentLiveHelpers.stream_ui_message(ui_msg)

    {:noreply, socket}
  end

  defp persist_authorized_folders(conversation_id, folders) do
    conversation = Conversations.get_conversation!(conversation_id)
    meta = conversation.meta || %{}
    new_meta = Map.put(meta, "authorized_folders", folders)
    Conversations.update_conversation(conversation, %{meta: new_meta})
  end

  defp restore_authorized_folders(conversation, session_id) do
    folders = get_in(conversation.meta || %{}, ["authorized_folders"]) || []

    Enum.each(folders, fn folder ->
      Cortex.Core.PermissionTracker.add_authorized_folder(session_id, folder)
    end)

    folders
  end

  @impl true
  def terminate(_reason, _socket) do
    # 🎯 Signal-Driven: Agent 由 SessionSupervisor 管理，无需手动清理
    # LiveView 不再持有 Agent PID，进程生命周期完全解耦
    :ok
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex-1 flex flex-col overflow-hidden bg-slate-950 text-slate-200">
      <header class="h-14 border-b border-slate-800 flex items-center px-6 justify-between bg-slate-900/50">
        <h2 class="text-sm font-semibold uppercase tracking-wider">Cortex</h2>
      </header>

      <main class="flex-1 overflow-hidden flex flex-col">
        <div class="bg-slate-900/30 border-b border-slate-800 px-6 py-2 flex space-x-4">
          <button
            phx-click="setActivePanel"
            phx-value-panel="chat"
            class="px-3 py-1 rounded-md bg-teal-600"
          >
            {gettext("Messages")}
          </button>
          <button phx-click="setActivePanel" phx-value-panel="tasks" class="px-3 py-1 rounded-md">
            {gettext("Tasks")}
          </button>
        </div>

        <div class="flex-1 overflow-hidden flex">
          <%= if @active_panel == "chat" do %>
            <div class="flex-1 flex overflow-hidden">
              <.chat_panel
                streams={@streams}
                models={@models}
                agents={@agents}
                selected_model_id={@selected_model_id}
                selected_agent_id={@selected_agent_id}
                is_thinking={@is_thinking}
                show_model_selector={@show_model_selector}
                show_agent_selector={@show_agent_selector}
                plan_mode_status={@plan_mode_status}
                show_permission_modal={@show_permission_modal}
                pending_permission_request={@pending_permission_request}
                authorized_paths={@authorized_paths}
                current_conversation_id={@current_conversation_id}
                archived_count={@archived_count}
                show_add_folder_modal={@show_add_folder_modal}
                new_folder_path={@new_folder_path}
                show_auth_management={@show_auth_management}
                authorized_paths_with_mode={@authorized_paths_with_mode}
                streaming_messages={@streaming_messages}
                pending_tool_calls_count={@pending_tool_calls_count}
                show_archived_modal={@show_archived_modal}
                archived_conversations={@archived_conversations}
              />
              <.permission_modal
                :if={@show_permission_modal}
                request={@pending_permission_request}
              />
              <.add_folder_modal
                :if={@show_add_folder_modal}
                folder_path={@new_folder_path}
              />
              <.archived_conversations_modal
                :if={@show_archived_modal}
                archived_conversations={@archived_conversations}
              />

              <%!-- <aside class="w-96 bg-slate-950 border-l border-slate-800 flex flex-col p-4 space-y-4 overflow-hidden hidden lg:flex">
                <div class="flex-1 min-h-0">
                  思考过程专门面板已注释
                  <.live_component
                    module={CortexWeb.Components.ThinkingComponent}
                    id="agent-thinking"
                    thinking_text={@plan_thought_text}
                  />

                </div>
                <div class="h-1/3 min-h-[200px]">
                  <.live_component
                    module={CortexWeb.Components.TerminalComponent}
                    id="shell-terminal"
                  />
                </div>
              </aside> --%>
            </div>
          <% end %>

          <%= if @active_panel == "tasks" do %>
            <div class="flex-1 p-6">
              <h2 class="text-xl font-bold mb-4">{gettext("Execution Status")}</h2>
              <%= for task <- @plan_todo_entries do %>
                <div class="p-3 border-b border-slate-800 flex justify-between">
                  <span>{task.content}</span>
                  <span class="text-teal-400">{task.status}</span>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </main>
    </div>
    """
  end
end
