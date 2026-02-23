defmodule CortexWeb.ModelLive.FormComponent do
  use CortexWeb, :live_component

  alias Cortex.Config
  alias Cortex.Config.{Metadata, LlmResolver}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="text-slate-200">
      <div class="mb-6">
        <h2 class="text-xl font-bold text-white">{@title}</h2>
      </div>

      <.form
        for={@form}
        id="model-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
        <div class="space-y-4">
          <div>
            <label class="block text-sm font-medium text-slate-300 mb-1">
              Provider Drive
            </label>
            <.input
              field={@form[:provider_drive]}
              type="select"
              options={@drive_options}
              prompt="Select drive instance"
              class="block w-full rounded-md border-slate-600 bg-slate-700 text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
            />
            <p class="mt-1 text-xs text-slate-500">Determines which base configuration logic this model uses</p>
          </div>

          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium text-slate-300 mb-1">Model Name (ID)</label>
              <.input
                field={@form[:name]}
                type="text"
                class="block w-full rounded-md border-slate-600 bg-slate-700 text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
                placeholder="例如: gpt-4-turbo"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-slate-300 mb-1">Display Name</label>
              <.input
                field={@form[:display_name]}
                type="text"
                class="block w-full rounded-md border-slate-600 bg-slate-700 text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
                placeholder="例如: GPT-4 Turbo"
              />
            </div>
          </div>

          <div>
            <label class="block text-sm font-medium text-slate-300 mb-1">Adapter (Provider Type)</label>
            <.input
              field={@form[:adapter]}
              type="select"
              options={[
                {"OpenAI", "openai"},
                {"Anthropic", "anthropic"},
                {"Google / Gemini", "gemini"},
                {"OpenRouter", "openrouter"},
                {"xAI", "xai"},
                {"Groq", "groq"},
                {"Mistral", "mistral"},
                {"DeepSeek", "deepseek"},
                {"Ollama", "ollama"},
                {"LM Studio", "lmstudio"},
                {"Cloudflare", "cloudflare"},
                {"Zenmux", "zenmux"},
                {"Kimi", "kimi"}
              ]}
              class="block w-full rounded-md border-slate-600 bg-slate-700 text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
            />
          </div>

          <div class="space-y-4 p-4 bg-slate-900/50 rounded-lg border border-slate-700">
            <h3 class="text-xs font-semibold text-slate-500 uppercase tracking-wider">Connection Config (Optional)</h3>
            <p class="text-xs text-slate-400">Prioritize configuration here. Leave blank to try Config and environment variables.</p>

            <div>
              <label class="block text-sm font-medium text-slate-300 mb-1">API Key</label>
              <.input
                field={@form[:api_key]}
                type="password"
                class="block w-full rounded-md border-slate-600 bg-slate-700 text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
                placeholder="sk-..."
              />
            </div>

            <div>
              <label class="block text-sm font-medium text-slate-300 mb-1">Base URL</label>
              <.input
                field={@form[:base_url]}
                type="text"
                class="block w-full rounded-md border-slate-600 bg-slate-700 text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
                placeholder={get_base_url_placeholder(@form)}
              />
            </div>
          </div>

          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium text-slate-300 mb-1">Context Window</label>
              <.input
                field={@form[:context_window]}
                type="number"
                class="block w-full rounded-md border-slate-600 bg-slate-700 text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
                placeholder="128000"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-slate-300 mb-1">Status</label>
              <.input
                field={@form[:status]}
                type="select"
                options={[
                  {"Active", "active"},
                  {"Beta", "beta"},
                  {"Alpha", "alpha"},
                  {"Deprecated", "deprecated"}
                ]}
                class="block w-full rounded-md border-slate-600 bg-slate-700 text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
              />
            </div>
          </div>

          <div class="flex items-center space-x-2">
            <.input
              field={@form[:enabled]}
              type="checkbox"
              class="h-4 w-4 rounded border-slate-600 bg-slate-700 text-teal-600 focus:ring-teal-500"
              label="Enable this model"
            />
          </div>
        </div>

        <div class="pt-4 flex justify-end space-x-3 border-t border-slate-700 mt-6">
          <.link
            patch={@patch}
            class="px-4 py-2 border border-slate-600 rounded-md text-sm font-medium text-slate-300 hover:bg-slate-700"
          >
            Cancel
          </.link>
          <button
            type="submit"
            phx-disable-with="Saving..."
            class="px-4 py-2 bg-teal-600 border border-transparent rounded-md text-sm font-medium text-white hover:bg-teal-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-teal-500"
          >
            Save Config
          </button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{model: model} = assigns, socket) do
    drive_options = Metadata.list_standard_drives() |> Enum.map(fn d -> {d.name, d.id} end)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:drive_options, drive_options)
     |> assign_new(:form, fn ->
       to_form(Config.change_llm_model(model))
     end)}
  end

  @impl true
  def handle_event("validate", %{"llm_model" => model_params}, socket) do
    # 自动联动逻辑：如果选择了 provider_drive 但没有选 adapter，自动填入默认 adapter
    model_params = maybe_auto_fill_adapter(model_params)

    changeset = Config.change_llm_model(socket.assigns.model, model_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"llm_model" => model_params}, socket) do
    save_model(socket, socket.assigns.action, model_params)
  end

  defp maybe_auto_fill_adapter(%{"provider_drive" => drive_id, "adapter" => ""} = params) do
    case Enum.find(Metadata.list_standard_drives(), &(&1.id == drive_id)) do
      nil -> params
      drive -> Map.put(params, "adapter", drive.adapter)
    end
  end

  defp maybe_auto_fill_adapter(params), do: params

  defp get_base_url_placeholder(form) do
    drive_id = form[:provider_drive].value
    adapter = form[:adapter].value

    drive = Enum.find(Metadata.list_standard_drives(), &(&1.id == drive_id))

    cond do
      drive && drive[:base_url] -> drive[:base_url]
      adapter -> LlmResolver.get_env_url(adapter) || LlmResolver.get_default_url(adapter)
      true -> "https://api.openai.com/v1"
    end
  end

  defp save_model(socket, :edit, model_params) do
    case Config.update_llm_model(socket.assigns.model, model_params) do
      {:ok, model} ->
        send(self(), {:saved, model})

        {:noreply,
         socket
         |> put_flash(:info, "Model updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_model(socket, :new, model_params) do
    model_params = Map.put(model_params, "source", "custom")

    case Config.create_llm_model(model_params) do
      {:ok, model} ->
        send(self(), {:saved, model})

        {:noreply,
         socket
         |> put_flash(:info, "Model created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
