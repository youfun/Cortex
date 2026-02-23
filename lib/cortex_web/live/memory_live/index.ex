defmodule CortexWeb.MemoryLive.Index do
  use CortexWeb, :live_view
  require Logger

  alias Cortex.Memory.WorkingMemory
  alias Cortex.Memory.Store
  alias Cortex.Memory.Proposal
  alias Cortex.Memory
  alias Cortex.SignalHub
  alias Cortex.Workspaces

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # 订阅信号
      SignalHub.subscribe("memory.working.saved")
      SignalHub.subscribe("memory.observation.created")
      SignalHub.subscribe("memory.observation.deleted")
      SignalHub.subscribe("memory.observation.updated")
      SignalHub.subscribe("memory.proposal.created")
    end

    workspace_root = Workspaces.workspace_root()

    socket =
      assign(socket,
        active_tab: :working,
        workspace_root: workspace_root,
        # Tab 1: Working Memory
        working_memory: load_working_memory(),
        # Tab 2: Observations
        observations_grouped: [],
        observations_days: 7,
        # Tab 3: Proposals
        proposals: [],
        # Tab 4: MEMORY.md
        memory_level: :global,
        memory_content: load_memory_content(workspace_root, :global),
        # Debounce timers
        reload_timer_working: nil,
        reload_timer_observations: nil,
        reload_timer_proposals: nil
      )
      |> load_observations()
      |> load_proposals()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :overview, _params) do
    assign(socket, page_title: "Memory")
  end

  # ============================================================================
  # Event Handlers - Tab Switching
  # ============================================================================

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: String.to_atom(tab))}
  end

  # ============================================================================
  # Event Handlers - Tab 1: Working Memory
  # ============================================================================

  @impl true
  def handle_event("remove_working_item", %{"id" => item_id}, socket) do
    :ok = WorkingMemory.remove(item_id)
    {:noreply, reload_working_memory(socket)}
  end

  @impl true
  def handle_event("clear_working_memory", _params, socket) do
    :ok = WorkingMemory.clear()
    {:noreply, reload_working_memory(socket)}
  end

  # ============================================================================
  # Event Handlers - Tab 2: Observations
  # ============================================================================

  @impl true
  def handle_event("delete_observation", %{"id" => obs_id}, socket) do
    case Store.delete_observation(obs_id) do
      :ok ->
        {:noreply, reload_observations(socket)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Observation not found")}
    end
  end

  @impl true
  def handle_event("load_more_observations", _params, socket) do
    new_days = socket.assigns.observations_days + 7
    {:noreply, assign(socket, observations_days: new_days) |> load_observations()}
  end

  # ============================================================================
  # Event Handlers - Tab 3: Proposals
  # ============================================================================

  @impl true
  def handle_event("accept_proposal", %{"id" => proposal_id}, socket) do
    case Store.accept_proposal(proposal_id) do
      {:ok, _observation} ->
        {:noreply, reload_proposals(socket) |> reload_observations()}

      {:ok, :already_accepted} ->
        {:noreply, put_flash(socket, :info, "Proposal already accepted")}

      {:error, reason} ->
        Logger.error("[MemoryLive] Failed to accept proposal: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to accept proposal")}
    end
  end

  @impl true
  def handle_event("reject_proposal", %{"id" => proposal_id}, socket) do
    case Proposal.reject(proposal_id) do
      {:ok, _proposal} ->
        {:noreply, reload_proposals(socket)}

      {:error, reason} ->
        Logger.error("[MemoryLive] Failed to reject proposal: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to reject proposal")}
    end
  end

  # ============================================================================
  # Event Handlers - Tab 4: MEMORY.md
  # ============================================================================

  @impl true
  def handle_event("switch_memory_level", %{"level" => level}, socket) do
    level_atom = String.to_atom(level)
    content = load_memory_content(socket.assigns.workspace_root, level_atom)

    {:noreply, assign(socket, memory_level: level_atom, memory_content: content)}
  end

  @impl true
  def handle_event("save_memory", %{"content" => content}, socket) do
    level = socket.assigns.memory_level
    workspace_root = socket.assigns.workspace_root

    case Memory.update_memory(workspace_root, level, content) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Memory saved successfully")}

      {:error, reason} ->
        Logger.error("[MemoryLive] Failed to save memory: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to save memory")}
    end
  end

  # ============================================================================
  # Signal Handlers - Real-time Updates
  # ============================================================================

  @impl true
  def handle_info({:signal, %Jido.Signal{type: type}}, socket) do
    case type do
      "memory.working.saved" ->
        schedule_debounced_reload(socket, :working)

      "memory.observation." <> _ ->
        schedule_debounced_reload(socket, :observations)

      "memory.proposal.created" ->
        schedule_debounced_reload(socket, :proposals)

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:debounced_reload, target}, socket) do
    case target do
      :working -> {:noreply, reload_working_memory(socket)}
      :observations -> {:noreply, reload_observations(socket)}
      :proposals -> {:noreply, reload_proposals(socket)}
    end
  end

  # ============================================================================
  # Private Functions - Data Loading
  # ============================================================================

  defp load_working_memory do
    WorkingMemory.list_all()
  end

  defp load_memory_content(workspace_root, level) do
    workspace_id = if level == :workspace, do: "default", else: nil
    Memory.load_memory(workspace_root, workspace_id)
  end

  defp load_observations(socket) do
    days = socket.assigns.observations_days
    observations = Store.load_observations(limit: 1000)
    grouped = group_observations_by_date(observations, days)
    assign(socket, observations_grouped: grouped)
  end

  defp load_proposals(socket) do
    proposals = Proposal.list_pending(limit: 50, order_by: :confidence)
    assign(socket, proposals: proposals)
  end

  defp group_observations_by_date(observations, days) do
    cutoff = Date.add(Date.utc_today(), -days)

    observations
    |> Enum.filter(fn obs -> Date.compare(DateTime.to_date(obs.timestamp), cutoff) != :lt end)
    |> Enum.group_by(fn obs -> DateTime.to_date(obs.timestamp) end)
    |> Enum.sort_by(fn {date, _} -> date end, {:desc, Date})
    |> Enum.map(fn {date, obs_list} ->
      # 每个日期组内按优先级排序
      sorted_obs =
        Enum.sort_by(obs_list, fn obs ->
          priority_order = %{high: 0, medium: 1, low: 2}
          Map.get(priority_order, obs.priority, 3)
        end)

      {date, sorted_obs}
    end)
  end

  # ============================================================================
  # Private Functions - Reload & Debounce
  # ============================================================================

  defp reload_working_memory(socket) do
    assign(socket, working_memory: load_working_memory())
  end

  defp reload_observations(socket) do
    load_observations(socket)
  end

  defp reload_proposals(socket) do
    load_proposals(socket)
  end

  defp schedule_debounced_reload(socket, target) do
    # 取消之前的定时器（如果有），100ms 内合并多次信号
    timer_key = :"reload_timer_#{target}"
    if old_timer = socket.assigns[timer_key], do: Process.cancel_timer(old_timer)
    timer = Process.send_after(self(), {:debounced_reload, target}, 100)
    {:noreply, assign(socket, timer_key, timer)}
  end

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full bg-slate-900 text-slate-200">
      <%!-- Header --%>
      <div class="flex items-center justify-between px-6 py-4 border-b border-slate-800">
        <h1 class="text-2xl font-semibold text-white">Memory System</h1>
      </div>

      <%!-- Tab Navigation --%>
      <div class="flex border-b border-slate-800 px-6">
        <button
          phx-click="switch_tab"
          phx-value-tab="working"
          class={[
            "px-4 py-3 text-sm font-medium transition-colors",
            @active_tab == :working && "text-teal-400 border-b-2 border-teal-400",
            @active_tab != :working && "text-slate-400 hover:text-white"
          ]}
        >
          Working Memory
        </button>
        <button
          phx-click="switch_tab"
          phx-value-tab="observations"
          class={[
            "px-4 py-3 text-sm font-medium transition-colors",
            @active_tab == :observations && "text-teal-400 border-b-2 border-teal-400",
            @active_tab != :observations && "text-slate-400 hover:text-white"
          ]}
        >
          Observations
        </button>
        <button
          phx-click="switch_tab"
          phx-value-tab="proposals"
          class={[
            "px-4 py-3 text-sm font-medium transition-colors",
            @active_tab == :proposals && "text-teal-400 border-b-2 border-teal-400",
            @active_tab != :proposals && "text-slate-400 hover:text-white"
          ]}
        >
          Proposals
        </button>
        <button
          phx-click="switch_tab"
          phx-value-tab="memory_file"
          class={[
            "px-4 py-3 text-sm font-medium transition-colors",
            @active_tab == :memory_file && "text-teal-400 border-b-2 border-teal-400",
            @active_tab != :memory_file && "text-slate-400 hover:text-white"
          ]}
        >
          MEMORY.md
        </button>
      </div>

      <%!-- Tab Content --%>
      <div class="flex-1 overflow-y-auto p-6">
        <%= if @active_tab == :working do %>
          <.working_memory_tab working_memory={@working_memory} />
        <% end %>

        <%= if @active_tab == :observations do %>
          <.observations_tab
            observations_grouped={@observations_grouped}
            observations_days={@observations_days}
          />
        <% end %>

        <%= if @active_tab == :proposals do %>
          <.proposals_tab proposals={@proposals} />
        <% end %>

        <%= if @active_tab == :memory_file do %>
          <.memory_file_tab
            memory_level={@memory_level}
            memory_content={@memory_content}
          />
        <% end %>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Components - Tab 2: Observations
  # ============================================================================

  defp observations_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <%= if Enum.empty?(@observations_grouped) do %>
        <div class="bg-slate-800 rounded-lg p-8 text-center">
          <p class="text-slate-500 italic">No observations in the last <%= @observations_days %> days</p>
        </div>
      <% else %>
        <%= for {date, observations} <- @observations_grouped do %>
          <div class="bg-slate-800 rounded-lg p-4">
            <h3 class="text-lg font-medium text-white mb-3">
              <%= Calendar.strftime(date, "%B %d, %Y") %>
              <span class="text-sm text-slate-400 ml-2">(<%= length(observations) %> items)</span>
            </h3>
            <ul class="space-y-3">
              <%= for obs <- observations do %>
                <li class="flex items-start gap-3 group">
                  <span class={[
                    "flex-shrink-0 w-2 h-2 rounded-full mt-2",
                    obs.priority == :high && "bg-red-500",
                    obs.priority == :medium && "bg-yellow-500",
                    obs.priority == :low && "bg-green-500"
                  ]}>
                  </span>
                  <div class="flex-1 min-w-0">
                    <p class="text-slate-300 break-words"><%= obs.content %></p>
                    <p class="text-xs text-slate-500 mt-1">
                      <%= Calendar.strftime(obs.timestamp, "%H:%M:%S") %>
                    </p>
                  </div>
                  <button
                    phx-click="delete_observation"
                    phx-value-id={obs.id}
                    data-confirm="Are you sure you want to delete this observation?"
                    class="flex-shrink-0 text-slate-400 hover:text-red-400 transition-colors opacity-0 group-hover:opacity-100"
                  >
                    <.icon name="hero-trash" class="w-4 h-4" />
                  </button>
                </li>
              <% end %>
            </ul>
          </div>
        <% end %>
      <% end %>

      <%!-- Load More Button --%>
      <div class="flex justify-center">
        <button
          phx-click="load_more_observations"
          class="px-4 py-2 bg-slate-800 hover:bg-slate-700 text-slate-300 rounded-lg transition-colors"
        >
          Load More (showing last <%= @observations_days %> days)
        </button>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Components - Tab 3: Proposals
  # ============================================================================

  defp proposals_tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <%= if Enum.empty?(@proposals) do %>
        <div class="bg-slate-800 rounded-lg p-8 text-center">
          <p class="text-slate-500 italic">No pending proposals</p>
        </div>
      <% else %>
        <%= for proposal <- @proposals do %>
          <div class="bg-slate-800 rounded-lg p-4">
            <div class="flex items-start justify-between mb-3">
              <div class="flex-1">
                <div class="flex items-center gap-2 mb-2">
                  <span class={[
                    "px-2 py-1 text-xs font-medium rounded",
                    proposal_type_class(proposal.type)
                  ]}>
                    <%= proposal.type %>
                  </span>
                  <span class={[
                    "px-2 py-1 text-xs font-medium rounded",
                    confidence_class(proposal.confidence)
                  ]}>
                    <%= Float.round(proposal.confidence * 100, 0) %>% confidence
                  </span>
                </div>
                <p class="text-slate-300"><%= proposal.content %></p>
                <%= if not Enum.empty?(proposal.evidence) do %>
                  <div class="mt-2">
                    <p class="text-xs text-slate-500 mb-1">Evidence:</p>
                    <ul class="text-xs text-slate-400 list-disc list-inside">
                      <%= for evidence <- Enum.take(proposal.evidence, 3) do %>
                        <li><%= evidence %></li>
                      <% end %>
                    </ul>
                  </div>
                <% end %>
              </div>
            </div>
            <div class="flex gap-2">
              <button
                phx-click="accept_proposal"
                phx-value-id={proposal.id}
                class="px-3 py-1.5 bg-teal-600 hover:bg-teal-700 text-white text-sm rounded transition-colors"
              >
                Accept
              </button>
              <button
                phx-click="reject_proposal"
                phx-value-id={proposal.id}
                data-confirm="Are you sure you want to reject this proposal?"
                class="px-3 py-1.5 bg-slate-700 hover:bg-slate-600 text-slate-300 text-sm rounded transition-colors"
              >
                Reject
              </button>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp proposal_type_class(type) do
    case type do
      :fact -> "bg-blue-600/20 text-blue-400"
      :insight -> "bg-purple-600/20 text-purple-400"
      :learning -> "bg-green-600/20 text-green-400"
      :pattern -> "bg-yellow-600/20 text-yellow-400"
      :preference -> "bg-pink-600/20 text-pink-400"
      _ -> "bg-slate-600/20 text-slate-400"
    end
  end

  defp confidence_class(confidence) do
    cond do
      confidence >= 0.8 -> "bg-green-600/20 text-green-400"
      confidence >= 0.5 -> "bg-yellow-600/20 text-yellow-400"
      true -> "bg-red-600/20 text-red-400"
    end
  end

  # ============================================================================
  # Components - Tab 1: Working Memory
  # ============================================================================

  defp working_memory_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Focus --%>
      <div class="bg-slate-800 rounded-lg p-4">
        <div class="flex items-center justify-between mb-3">
          <h3 class="text-lg font-medium text-white">Current Focus</h3>
          <%= if @working_memory.focus do %>
            <button
              phx-click="remove_working_item"
              phx-value-id={@working_memory.focus.id}
              class="text-slate-400 hover:text-red-400 transition-colors"
            >
              <.icon name="hero-x-mark" class="w-5 h-5" />
            </button>
          <% end %>
        </div>
        <%= if @working_memory.focus do %>
          <p class="text-slate-300"><%= @working_memory.focus.content %></p>
        <% else %>
          <p class="text-slate-500 italic">No current focus</p>
        <% end %>
      </div>

      <%!-- Curiosities --%>
      <div class="bg-slate-800 rounded-lg p-4">
        <h3 class="text-lg font-medium text-white mb-3">Curiosities</h3>
        <%= if Enum.empty?(@working_memory.curiosities) do %>
          <p class="text-slate-500 italic">No curiosities</p>
        <% else %>
          <ul class="space-y-2">
            <%= for item <- @working_memory.curiosities do %>
              <li class="flex items-start justify-between group">
                <span class="text-slate-300 flex-1"><%= item.content %></span>
                <button
                  phx-click="remove_working_item"
                  phx-value-id={item.id}
                  class="ml-2 text-slate-400 hover:text-red-400 transition-colors opacity-0 group-hover:opacity-100"
                >
                  <.icon name="hero-x-mark" class="w-4 h-4" />
                </button>
              </li>
            <% end %>
          </ul>
        <% end %>
      </div>

      <%!-- Concerns --%>
      <div class="bg-slate-800 rounded-lg p-4">
        <h3 class="text-lg font-medium text-white mb-3">Concerns</h3>
        <%= if Enum.empty?(@working_memory.concerns) do %>
          <p class="text-slate-500 italic">No concerns</p>
        <% else %>
          <ul class="space-y-2">
            <%= for item <- @working_memory.concerns do %>
              <li class="flex items-start justify-between group">
                <span class="text-slate-300 flex-1"><%= item.content %></span>
                <button
                  phx-click="remove_working_item"
                  phx-value-id={item.id}
                  class="ml-2 text-slate-400 hover:text-red-400 transition-colors opacity-0 group-hover:opacity-100"
                >
                  <.icon name="hero-x-mark" class="w-4 h-4" />
                </button>
              </li>
            <% end %>
          </ul>
        <% end %>
      </div>

      <%!-- Goals --%>
      <div class="bg-slate-800 rounded-lg p-4">
        <h3 class="text-lg font-medium text-white mb-3">Goals</h3>
        <%= if Enum.empty?(@working_memory.goals) do %>
          <p class="text-slate-500 italic">No goals</p>
        <% else %>
          <ul class="space-y-2">
            <%= for item <- @working_memory.goals do %>
              <li class="flex items-start justify-between group">
                <span class="text-slate-300 flex-1"><%= item.content %></span>
                <button
                  phx-click="remove_working_item"
                  phx-value-id={item.id}
                  class="ml-2 text-slate-400 hover:text-red-400 transition-colors opacity-0 group-hover:opacity-100"
                >
                  <.icon name="hero-x-mark" class="w-4 h-4" />
                </button>
              </li>
            <% end %>
          </ul>
        <% end %>
      </div>

      <%!-- Clear All Button --%>
      <div class="flex justify-end">
        <button
          phx-click="clear_working_memory"
          data-confirm="Are you sure you want to clear all working memory?"
          class="px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded-lg transition-colors"
        >
          Clear All
        </button>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Components - Tab 4: MEMORY.md
  # ============================================================================

  defp memory_file_tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <%!-- Level Selector --%>
      <div class="flex gap-2">
        <button
          phx-click="switch_memory_level"
          phx-value-level="global"
          class={[
            "px-4 py-2 rounded-lg text-sm font-medium transition-colors",
            @memory_level == :global && "bg-teal-600 text-white",
            @memory_level != :global && "bg-slate-800 text-slate-300 hover:bg-slate-700"
          ]}
        >
          Global
        </button>
        <button
          phx-click="switch_memory_level"
          phx-value-level="workspace"
          class={[
            "px-4 py-2 rounded-lg text-sm font-medium transition-colors",
            @memory_level == :workspace && "bg-teal-600 text-white",
            @memory_level != :workspace && "bg-slate-800 text-slate-300 hover:bg-slate-700"
          ]}
        >
          Workspace
        </button>
      </div>

      <%!-- Editor --%>
      <form phx-submit="save_memory" class="space-y-4">
        <textarea
          name="content"
          rows="20"
          class="w-full px-4 py-3 bg-slate-800 text-slate-200 rounded-lg border border-slate-700 focus:border-teal-500 focus:ring-1 focus:ring-teal-500 font-mono text-sm"
          placeholder="Enter memory content..."
        ><%= @memory_content %></textarea>

        <div class="flex justify-end">
          <button
            type="submit"
            class="px-4 py-2 bg-teal-600 hover:bg-teal-700 text-white rounded-lg transition-colors"
          >
            Save
          </button>
        </div>
      </form>
    </div>
    """
  end
end
