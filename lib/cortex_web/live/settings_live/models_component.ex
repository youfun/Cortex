defmodule CortexWeb.SettingsLive.ModelsComponent do
  use CortexWeb, :live_component

  alias Cortex.Config
  alias Cortex.Config.{Settings, Metadata}

  @impl true
  def update(_assigns, socket) do
    Metadata.reload()

    {:ok,
     socket
     |> assign(:models, list_models())
     |> assign(:filter_adapter, nil)
     |> assign(:filter_status, nil)
     |> assign(:model, nil)
     |> assign(:live_action, :index)}
  end

  @impl true
  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    model = Config.get_llm_model!(id)

    case model.enabled do
      true -> Settings.disable_model(model.name)
      false -> Settings.enable_model(model.name)
    end

    Metadata.reload()

    {:noreply, assign(socket, :models, list_models())}
  end

  def handle_event("filter", %{"adapter" => adapter, "status" => status}, socket) do
    filter_adapter = if adapter == "", do: nil, else: adapter
    filter_status = if status == "", do: nil, else: status

    {:noreply,
     socket
     |> assign(:filter_adapter, filter_adapter)
     |> assign(:filter_status, filter_status)
     |> assign(:models, list_models(filter_adapter, filter_status))}
  end

  defp list_models(filter_adapter \\ nil, filter_status \\ nil) do
    all_models = Metadata.get_all_models()

    all_models
    |> Enum.filter(fn m ->
      (is_nil(filter_adapter) || m.adapter == filter_adapter) &&
        (is_nil(filter_status) || m.status == filter_status)
    end)
    |> Enum.sort_by(& &1.name)
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :all_adapters,
        ~w(openai anthropic gemini google google_vertex openrouter xai groq mistral deepseek ollama lmstudio cloudflare zenmux kimi)
      )

    ~H"""
    <div class="flex-1 flex flex-col overflow-hidden bg-slate-950">
      <!-- Header -->
      <header class="h-14 border-b border-slate-800 flex items-center px-6 justify-between bg-slate-900/50 backdrop-blur-md">
        <div class="flex items-center space-x-3">
          <h2 class="text-sm font-semibold text-slate-400 uppercase tracking-wider">
            Model Management
          </h2>
        </div>

        <div class="flex items-center space-x-4">
          <div class="flex items-center space-x-2 px-3 py-1 bg-slate-800 rounded-full text-xs">
            <div class="w-2 h-2 bg-green-500 rounded-full animate-pulse"></div>
            <span>Connected</span>
          </div>
        </div>
      </header>

      <!-- Page Content -->
      <main class="flex-1 overflow-y-auto relative h-full">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <div class="sm:flex sm:items-center sm:justify-between mb-8">
            <div>
              <h1 class="text-3xl font-bold text-white">Model Management</h1>
              <p class="mt-2 text-sm text-slate-400">
                Manage available LLM models and their status
              </p>
            </div>
            <div class="mt-4 sm:mt-0 flex space-x-3">
              <.link
                patch={~p"/settings/models/new"}
                class="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-green-600 hover:bg-green-700 transition-colors"
              >
                <.icon name="hero-plus" class="-ml-1 mr-2 h-4 w-4" /> New Model
              </.link>
            </div>
          </div>
          
    <!-- Filters -->
          <div class="mb-6 flex space-x-4 bg-slate-800 p-4 rounded-lg border border-slate-700">
            <form phx-change="filter" phx-target={@myself} class="flex space-x-4 w-full">
              <div class="flex-1 max-w-xs">
                <label class="block text-xs font-medium text-slate-400 mb-1">Provider Type (Adapter) Filter</label>
                <select
                  name="adapter"
                  class="block w-full rounded-md border-slate-600 bg-slate-700 text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
                >
                  <option value="">All Types</option>
                  <%= for a <- @all_adapters do %>
                    <option value={a} selected={@filter_adapter == a}>{a}</option>
                  <% end %>
                </select>
              </div>

              <div class="flex-1 max-w-xs">
                <label class="block text-xs font-medium text-slate-400 mb-1">Status Filter</label>
                <select
                  name="status"
                  class="block w-full rounded-md border-slate-600 bg-slate-700 text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
                >
                  <option value="">All Status</option>
                  <option value="active" selected={@filter_status == "active"}>Active</option>
                  <option value="beta" selected={@filter_status == "beta"}>Beta</option>
                  <option value="alpha" selected={@filter_status == "alpha"}>Alpha</option>
                  <option value="deprecated" selected={@filter_status == "deprecated"}>
                    Deprecated
                  </option>
                </select>
              </div>
            </form>
          </div>

          <div class="bg-slate-800 shadow-sm rounded-lg overflow-hidden border border-slate-700">
            <table class="min-w-full divide-y divide-slate-700">
              <thead class="bg-slate-900">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-slate-400 uppercase tracking-wider">
                    Model Name
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-slate-400 uppercase tracking-wider">
                    Provider Drive
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-slate-400 uppercase tracking-wider">
                    Adapter
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-slate-400 uppercase tracking-wider">
                    Status
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-slate-400 uppercase tracking-wider">
                    Config
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-slate-400 uppercase tracking-wider">
                    Enabled
                  </th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-slate-400 uppercase tracking-wider">
                    Action
                  </th>
                </tr>
              </thead>
              <tbody class="bg-slate-800 divide-y divide-slate-700">
                <tr :for={model <- @models} class="hover:bg-slate-700/50 transition-colors">
                  <td class="px-6 py-4 whitespace-nowrap">
                    <div class="text-sm font-medium text-white">{model.display_name || model.name}</div>
                    <div class="text-xs text-slate-500">{model.name}</div>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-slate-300">
                    {model.provider_drive}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-slate-400">
                    <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-slate-700 text-slate-300 border border-slate-600">
                      {model.adapter}
                    </span>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full border #{status_color(model.status)}"}>
                      {model.status}
                    </span>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-xs text-slate-400">
                    <div class="flex flex-col space-y-1">
                      <div class="flex items-center">
                        <span class="w-12">URL:</span>
                        <span class={if model.base_url, do: "text-green-400", else: "text-slate-600"}>
                          {if model.base_url, do: "Custom", else: "Default"}
                        </span>
                      </div>
                      <div class="flex items-center">
                        <span class="w-12">Key:</span>
                        <span class={if model.api_key, do: "text-green-400", else: "text-slate-600"}>
                          {if model.api_key, do: "Custom", else: "Env"}
                        </span>
                      </div>
                    </div>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <button
                      phx-click="toggle_enabled"
                      phx-value-id={model.id}
                      phx-target={@myself}
                      class={[
                        "px-2 inline-flex text-xs leading-5 font-semibold rounded-full border transition-colors",
                        model.enabled && "bg-green-900 text-green-200 border-green-800",
                        !model.enabled && "bg-slate-700 text-slate-400 border-slate-600"
                      ]}
                    >
                      {if model.enabled, do: "Enabled", else: "Disabled"}
                    </button>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                    <div class="flex justify-end space-x-3">
                      <.link
                        patch={~p"/settings/models/new?copy_id=#{model.id}"}
                        class="text-slate-300 hover:text-white transition-colors"
                      >
                        Copy
                      </.link>
                      <.link
                        patch={~p"/settings/models/#{model.id}/edit"}
                        class="text-teal-400 hover:text-teal-300 transition-colors"
                      >
                        Edit
                      </.link>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </main>
    </div>
    """
  end

  defp status_color("active"),
    do: "bg-green-900 text-green-200 border-green-800"

  defp status_color("beta"),
    do: "bg-yellow-900 text-yellow-200 border-yellow-800"

  defp status_color("alpha"),
    do: "bg-orange-900 text-orange-200 border-orange-800"

  defp status_color("deprecated"), do: "bg-red-900 text-red-200 border-red-800"
  defp status_color(_), do: "bg-slate-700 text-slate-300 border-slate-600"
end
