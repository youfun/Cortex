defmodule CortexWeb.JidoComponents.AgentsPanel do
  @moduledoc """
  Agents Fleet Panel component.
  """
  use CortexWeb, :html

  @doc """
  Agents Fleet Panel component.
  """
  def agents_panel(assigns) do
    ~H"""
    <div class="flex-1 p-8 overflow-y-auto">
      <div class="max-w-4xl mx-auto">
        <div class="flex items-center justify-between mb-8">
          <h1 class="text-2xl font-bold">Agent Fleet</h1>
          <button class="bg-teal-600 hover:bg-teal-500 px-4 py-2 rounded-lg text-sm font-medium transition-colors">
            Register New Agent
          </button>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <%= for agent <- @agents do %>
            <div class="bg-slate-800 border border-slate-700 rounded-2xl p-6 hover:border-slate-500 transition-all group">
              <div class="flex items-start justify-between mb-4">
                <div class="w-12 h-12 bg-slate-700 rounded-xl flex items-center justify-center text-teal-400 group-hover:bg-teal-600 group-hover:text-white transition-colors">
                  <.icon name="hero-user-group" class="w-6 h-6" />
                </div>
                <div class={[
                  "px-2 py-1 rounded text-[10px] font-bold uppercase",
                  agent.status == "online" && "bg-green-500/10 text-green-500",
                  agent.status != "online" && "bg-slate-700 text-slate-400"
                ]}>
                  {agent.status}
                </div>
              </div>
              <h3 class="text-lg font-bold mb-1">{agent.name}</h3>
              <p class="text-sm text-slate-400 mb-6 line-clamp-2">{agent.description}</p>
              <div class="flex items-center justify-between pt-4 border-t border-slate-700">
                <span class="text-xs text-slate-500">{agent.sessions_count} sessions</span>
                <button class="text-teal-400 hover:text-teal-300 text-sm font-medium">
                  Configure
                </button>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
