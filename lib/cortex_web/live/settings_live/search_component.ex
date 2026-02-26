defmodule CortexWeb.SettingsLive.SearchComponent do
  use CortexWeb, :live_component

  alias Cortex.Config.SearchSettings
  alias Cortex.Config.Settings

  @impl true
  def update(_assigns, socket) do
    settings = SearchSettings.get_settings()

    form_data = %{
      "default_provider" => settings.default_provider || "tavily",
      "brave_api_key" => settings.brave_api_key || "",
      "tavily_api_key" => settings.tavily_api_key || "",
      "enable_llm_title_generation" => settings.enable_llm_title_generation || false,
      "title_generation" => Settings.get_title_generation(),
      "title_model" => Settings.get_title_model() || ""
    }

    {:ok,
     socket
     |> assign(:form, to_form(form_data))
     |> assign(:saved, false)}
  end

  @impl true
  def handle_event("save", params, socket) do
    search_attrs = %{
      default_provider: params["default_provider"],
      brave_api_key: params["brave_api_key"],
      tavily_api_key: params["tavily_api_key"],
      enable_llm_title_generation: params["enable_llm_title_generation"] == "true"
    }

    title_generation = params["title_generation"] || "disabled"
    title_model = params["title_model"] || ""

    Settings.set_title_generation(title_generation)
    if title_model != "", do: Settings.set_title_model(title_model)

    case SearchSettings.update_settings(search_attrs) do
      {:ok, _} ->
        {:noreply, assign(socket, :saved, true)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex-1 flex flex-col overflow-hidden bg-slate-950">
      <div class="flex-1 overflow-y-auto p-6">
        <div class="mx-auto max-w-2xl">
          <h1 class="text-2xl font-bold mb-8 text-slate-100">Search Settings</h1>

          <.form for={@form} phx-submit="save" phx-target={@myself} class="space-y-8">
            <%!-- Search Provider --%>
            <div class="bg-slate-900 border border-slate-800 p-6 rounded-xl space-y-4">
              <h2 class="text-base font-semibold text-slate-200">Web Search Provider</h2>

              <div>
                <label class="block text-sm text-slate-400 mb-1">Default Provider</label>
                <select
                  name="default_provider"
                  class="w-full bg-slate-800 border border-slate-700 rounded-lg px-3 py-2 text-slate-200 text-sm focus:outline-none focus:border-teal-500"
                >
                  <option value="tavily" selected={@form[:default_provider].value == "tavily"}>Tavily</option>
                  <option value="brave" selected={@form[:default_provider].value == "brave"}>Brave</option>
                </select>
              </div>

              <div>
                <label class="block text-sm text-slate-400 mb-1">Tavily API Key</label>
                <input
                  type="password"
                  name="tavily_api_key"
                  value={@form[:tavily_api_key].value}
                  placeholder="tvly-..."
                  class="w-full bg-slate-800 border border-slate-700 rounded-lg px-3 py-2 text-slate-200 text-sm focus:outline-none focus:border-teal-500"
                />
              </div>

              <div>
                <label class="block text-sm text-slate-400 mb-1">Brave API Key</label>
                <input
                  type="password"
                  name="brave_api_key"
                  value={@form[:brave_api_key].value}
                  placeholder="BSA..."
                  class="w-full bg-slate-800 border border-slate-700 rounded-lg px-3 py-2 text-slate-200 text-sm focus:outline-none focus:border-teal-500"
                />
              </div>
            </div>

            <%!-- Title Generation --%>
            <div class="bg-slate-900 border border-slate-800 p-6 rounded-xl space-y-4">
              <h2 class="text-base font-semibold text-slate-200">Conversation Title Generation</h2>

              <div>
                <label class="block text-sm text-slate-400 mb-1">Mode</label>
                <select
                  name="title_generation"
                  class="w-full bg-slate-800 border border-slate-700 rounded-lg px-3 py-2 text-slate-200 text-sm focus:outline-none focus:border-teal-500"
                >
                  <option value="disabled" selected={@form[:title_generation].value == "disabled"}>Disabled</option>
                  <option value="conversation" selected={@form[:title_generation].value == "conversation"}>Use conversation model</option>
                  <option value="model" selected={@form[:title_generation].value == "model"}>Use specific model</option>
                </select>
              </div>

              <div>
                <label class="block text-sm text-slate-400 mb-1">Title Model (for "specific model" mode)</label>
                <input
                  type="text"
                  name="title_model"
                  value={@form[:title_model].value}
                  placeholder="e.g. gpt-4o-mini"
                  class="w-full bg-slate-800 border border-slate-700 rounded-lg px-3 py-2 text-slate-200 text-sm focus:outline-none focus:border-teal-500"
                />
              </div>
            </div>

            <div class="flex items-center gap-4">
              <button
                type="submit"
                class="px-4 py-2 bg-teal-600 hover:bg-teal-500 text-white text-sm font-medium rounded-lg transition-colors"
              >
                Save
              </button>
              <span :if={@saved} class="text-sm text-teal-400">Saved.</span>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end
end
