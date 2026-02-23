defmodule CortexWeb.Components.ModelSelector do
  @moduledoc """
  可复用的 Model 选择器组件

  ## 使用示例

      <.model_selector
        id="skill-model-selector"
        selected={@selected_model}
        on_select={fn model -> send(self(), {:model_selected, model}) end}
        filter_enabled={true}
      />
  """

  use Phoenix.Component
  alias Cortex.Config
  alias Cortex.Config.{Settings, Metadata}

  attr :id, :string, required: true
  attr :selected, :string, default: nil
  attr :filter_enabled, :boolean, default: true
  attr :class, :string, default: ""
  attr :label, :string, default: "选择模型"

  def model_selector(assigns) do
    models =
      if assigns.filter_enabled do
        Settings.list_available_models()
      else
        Config.list_llm_models()
      end

    # 按 provider 分组
    grouped_models =
      models
      |> Enum.group_by(& &1.provider_name)
      |> Enum.sort_by(fn {provider_name, _} -> provider_name end)

    assigns = assign(assigns, :grouped_models, grouped_models)

    ~H"""
    <div class={@class}>
      <label for={@id} class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
        {@label}
      </label>
      <select
        id={@id}
        name={@id}
        class="block w-full rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-700 dark:text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
      >
        <option value="">-- 请选择模型 --</option>
        <%= for {provider_name, models} <- @grouped_models do %>
          <optgroup label={String.capitalize(provider_name)}>
            <%= for model <- models do %>
              <option value={model.name} selected={model.name == @selected}>
                {model.display_name || model.name}
                <%= if model.context_window do %>
                  ({format_context_window(model.context_window)})
                <% end %>
              </option>
            <% end %>
          </optgroup>
        <% end %>
      </select>

      <%= if @selected do %>
        <div class="mt-2 p-3 bg-gray-50 dark:bg-gray-800 rounded-md">
          <%= case Metadata.get_model(@selected) do %>
            <% nil -> %>
              <p class="text-sm text-gray-500 dark:text-gray-400">模型未找到</p>
            <% model -> %>
              <div class="space-y-1">
                <div class="flex justify-between text-sm">
                  <span class="text-gray-600 dark:text-gray-400">Provider:</span>
                  <span class="font-medium text-gray-900 dark:text-white">{model.provider_name}</span>
                </div>
                <%= if model.context_window do %>
                  <div class="flex justify-between text-sm">
                    <span class="text-gray-600 dark:text-gray-400">上下文窗口:</span>
                    <span class="font-medium text-gray-900 dark:text-white">
                      {format_context_window(model.context_window)}
                    </span>
                  </div>
                <% end %>
                <%= if model.capabilities && map_size(model.capabilities) > 0 do %>
                  <div class="flex flex-wrap gap-1 mt-2">
                    <%= for {cap, enabled} <- model.capabilities, enabled do %>
                      <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200">
                        {cap}
                      </span>
                    <% end %>
                  </div>
                <% end %>
              </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_context_window(window) when window >= 1_000_000 do
    "#{div(window, 1_000_000)}M"
  end

  defp format_context_window(window) when window >= 1_000 do
    "#{div(window, 1_000)}K"
  end

  defp format_context_window(window), do: "#{window}"
end
