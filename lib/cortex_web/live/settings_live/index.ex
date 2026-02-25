defmodule CortexWeb.SettingsLive.Index do
  use CortexWeb, :live_view

  alias Cortex.{Conversations, Workspaces, Config}

  @impl true
  def mount(_params, _session, socket) do
    workspace = Workspaces.ensure_default_workspace()
    conversations = Conversations.list_conversations(workspace.id)
    archived_count = Conversations.count_archived(workspace.id)

    {:ok,
     socket
     |> assign(:active_tab, :settings)
     |> assign(:workspace, workspace)
     |> assign(:archived_count, archived_count)
     |> assign(:page_title, "Settings")
     |> assign(:model, nil)
     |> stream(:conversations, conversations)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :channels, _params) do
    assign(socket, :page_title, "Channel Settings")
  end

  defp apply_action(socket, :search, _params) do
    assign(socket, :page_title, "Search Settings")
  end

  defp apply_action(socket, :models, _params) do
    assign(socket, :page_title, "Model Management")
  end

  defp apply_action(socket, :new_model, %{"copy_id" => id}) do
    source_model = Config.get_llm_model!(id)

    socket
    |> assign(:page_title, "Copy Model")
    |> assign(:model, build_copy_model(source_model))
  end

  defp apply_action(socket, :new_model, _params) do
    socket
    |> assign(:page_title, "New Model")
    |> assign(:model, %Config.LlmModel{source: "custom", status: "active", enabled: true})
  end

  defp apply_action(socket, :edit_model, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Model")
    |> assign(:model, Config.get_llm_model!(id))
  end

  @impl true
  def handle_event("new_conversation", _, socket) do
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  def handle_event("switch_conversation", %{"id" => _id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  def handle_event("delete_conversation", %{"id" => id}, socket) do
    case Conversations.get_conversation(id) do
      nil ->
        {:noreply, socket}

      conv ->
        Conversations.delete_conversation(conv)
        {:noreply, stream_delete(socket, :conversations, conv)}
    end
  end

  def handle_event("archive_conversation", %{"id" => id}, socket) do
    case Conversations.get_conversation(id) do
      nil ->
        {:noreply, socket}

      conv ->
        Conversations.archive_conversation(conv)
        archived_count = Conversations.count_archived(socket.assigns.workspace.id)

        {:noreply,
         socket
         |> stream_delete(:conversations, conv)
         |> assign(:archived_count, archived_count)}
    end
  end

  def handle_event("show_archived", _, socket) do
    {:noreply, socket}
  end

  def handle_event("shutdown", _, socket) do
    System.stop(0)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:saved, _model}, socket) do
    Config.Metadata.reload()
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-full bg-slate-950">
      <%!-- Secondary Sidebar (200px) --%>
      <aside class="w-50 bg-slate-900 border-r border-slate-800 flex flex-col">
        <div class="h-14 flex items-center px-6 border-b border-slate-800">
          <h2 class="text-sm font-semibold text-slate-200 uppercase tracking-wider">Settings</h2>
        </div>

        <nav class="flex-1 p-4 space-y-1">
          <.link
            patch={~p"/settings/channels"}
            class={[
              "flex items-center gap-3 px-4 py-3 rounded-lg transition-colors",
              @live_action == :channels && "bg-teal-600/10 text-teal-400 border-l-2 border-teal-500",
              @live_action != :channels && "text-slate-400 hover:bg-slate-800 hover:text-white"
            ]}
          >
            <.icon name="hero-chat-bubble-left-right" class="w-5 h-5" />
            <span class="text-sm font-medium">Channels</span>
          </.link>

          <.link
            patch={~p"/settings/models"}
            class={[
              "flex items-center gap-3 px-4 py-3 rounded-lg transition-colors",
              @live_action == :models && "bg-teal-600/10 text-teal-400 border-l-2 border-teal-500",
              @live_action != :models && "text-slate-400 hover:bg-slate-800 hover:text-white"
            ]}
          >
            <.icon name="hero-cpu-chip" class="w-5 h-5" />
            <span class="text-sm font-medium">Models</span>
          </.link>

          <.link
            patch={~p"/settings/search"}
            class={[
              "flex items-center gap-3 px-4 py-3 rounded-lg transition-colors",
              @live_action == :search && "bg-teal-600/10 text-teal-400 border-l-2 border-teal-500",
              @live_action != :search && "text-slate-400 hover:bg-slate-800 hover:text-white"
            ]}
          >
            <.icon name="hero-magnifying-glass" class="w-5 h-5" />
            <span class="text-sm font-medium">Search</span>
          </.link>
        </nav>
      </aside>

      <%!-- Content Area --%>
      <div class="flex-1 overflow-hidden">
        <%= case @live_action do %>
          <% :channels -> %>
            <.live_component
              module={CortexWeb.SettingsLive.ChannelsComponent}
              id="channels-settings"
            />
          <% action when action in [:models, :new_model, :edit_model] -> %>
            <.live_component
              module={CortexWeb.SettingsLive.ModelsComponent}
              id="models-settings"
            />
            <.model_modal
              :if={action in [:new_model, :edit_model]}
              model={@model}
              page_title={@page_title}
              live_action={action}
              patch={~p"/settings/models"}
            />
          <% :search -> %>
            <.live_component
              module={CortexWeb.SettingsLive.SearchComponent}
              id="search-settings"
            />
        <% end %>
      </div>
    </div>
    """
  end

  defp model_modal(assigns) do
    # Convert :new_model/:edit_model to :new/:edit for FormComponent
    action = case assigns.live_action do
      :new_model -> :new
      :edit_model -> :edit
      other -> other
    end
    
    assigns = assign(assigns, :form_action, action)
    
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center"
      style="display:flex;align-items:center;justify-content:center;"
    >
      <%!-- Backdrop --%>
      <div
        class="fixed inset-0 bg-slate-900/80 backdrop-blur-sm transition-opacity"
        aria-hidden="true"
        phx-click={JS.patch(@patch)}
      >
      </div>

      <%!-- Modal Panel --%>
      <div class="relative w-full max-w-lg mx-4 transform overflow-hidden rounded-lg bg-slate-800 border border-slate-700 p-6 text-left shadow-xl transition-all z-10">
        <.live_component
          module={CortexWeb.ModelLive.FormComponent}
          id={@model.id || :new}
          title={@page_title}
          action={@form_action}
          model={@model}
          patch={@patch}
        />
      </div>
    </div>
    """
  end

  defp build_copy_model(source_model) do
    base_name =
      source_model.name
      |> default_copy_base("model")

    display_base =
      source_model.display_name
      |> default_copy_base(source_model.name || "Model")

    %Config.LlmModel{
      name: "#{base_name}-copy",
      display_name: "#{display_base} Copy",
      provider_drive: source_model.provider_drive,
      adapter: source_model.adapter,
      api_key: source_model.api_key,
      base_url: source_model.base_url,
      status: source_model.status || "active",
      context_window: source_model.context_window,
      enabled: source_model.enabled,
      source: "custom"
    }
  end

  defp default_copy_base(nil, fallback), do: fallback
  defp default_copy_base("", fallback), do: fallback
  defp default_copy_base(value, _fallback), do: value
end
