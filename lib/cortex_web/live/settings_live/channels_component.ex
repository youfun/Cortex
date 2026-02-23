defmodule CortexWeb.SettingsLive.ChannelsComponent do
  use CortexWeb, :live_component

  import CortexWeb.SettingsLive.ChannelsForms

  alias Cortex.Channels

  @impl true
  def update(_assigns, socket) do
    configs = Channels.list_channel_configs()

    {:ok,
     socket
     |> assign(:configs, configs)
     |> assign(:active_tab, :telegram)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, parse_tab(tab))}
  end

  @impl true
  def handle_event("save", params, socket) do
    {:noreply, save_channel_config(params, socket, &reload_configs/1)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex-1 flex flex-col overflow-hidden bg-slate-950">
      <div class="flex-1 overflow-y-auto p-6">
        <div class="mx-auto max-w-5xl">
          <h1 class="text-2xl font-bold mb-8 text-slate-100">Channel Settings</h1>
          
    <!-- Tabs -->
          <div class="border-b border-slate-700 mb-6">
            <nav class="-mb-px flex space-x-8" aria-label="Tabs">
              <%= for tab <- [:telegram, :feishu] do %>
                <button
                  phx-click="switch_tab"
                  phx-value-tab={tab}
                  phx-target={@myself}
                  class={[
                    @active_tab == tab && "border-teal-500 text-teal-400",
                    @active_tab != tab &&
                      "border-transparent text-slate-400 hover:text-slate-300 hover:border-slate-600",
                    "whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm capitalize transition-colors"
                  ]}
                >
                  {tab}
                </button>
              <% end %>
            </nav>
          </div>
          
    <!-- Tab Content -->
          <div class="bg-slate-900 border border-slate-800 p-8 rounded-xl">
            <%= case @active_tab do %>
              <% :telegram -> %>
                <.telegram_form configs={@configs} target={@myself} />
              <% :feishu -> %>
                <.feishu_form configs={@configs} target={@myself} />
              <% _ -> %>
                <.telegram_form configs={@configs} target={@myself} />
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp reload_configs(socket) do
    assign(socket, :configs, Channels.list_channel_configs())
  end
end
