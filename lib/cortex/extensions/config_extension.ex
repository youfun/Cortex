defmodule Cortex.Extensions.ConfigExtension do
  @behaviour Cortex.Extensions.Extension

  def name, do: "config"
  def description, do: "LLM-accessible configuration tools for channels, models, and search"
  def hooks, do: []

  def tools do
    [
      %Cortex.Tools.Tool{
        name: "update_channel_config",
        description: "Update SNS channel configuration (Telegram, Feishu, Discord, etc.).",
        parameters: [
          adapter: [type: :string, required: true, doc: "Channel adapter: telegram | feishu | discord | dingtalk | wecom"],
          enabled: [type: :boolean, required: false, doc: "Enable or disable this channel"],
          config: [type: :map, required: false, doc: "Channel-specific config map"]
        ],
        module: Cortex.Tools.Handlers.UpdateChannelConfig
      },
      %Cortex.Tools.Tool{
        name: "update_model_config",
        description: "Update LLM model configuration (enable/disable, set default).",
        parameters: [
          model_name: [type: :string, required: true, doc: "Model name"],
          action: [type: :string, required: false, doc: "Action: enable | disable | set_default | update (default: update)"]
        ],
        module: Cortex.Tools.Handlers.UpdateModelConfig
      },
      %Cortex.Tools.Tool{
        name: "update_search_config",
        description: "Update web search configuration (default provider, API keys).",
        parameters: [
          default_provider: [type: :string, required: false, doc: "Default search provider: brave | tavily"],
          brave_api_key: [type: :string, required: false, doc: "Brave Search API key"],
          tavily_api_key: [type: :string, required: false, doc: "Tavily Search API key"],
          enable_llm_title_generation: [type: :boolean, required: false, doc: "Enable LLM-generated titles"]
        ],
        module: Cortex.Tools.Handlers.UpdateSearchConfig
      },
      %Cortex.Tools.Tool{
        name: "get_system_config",
        description: "Read current system configuration (channels, models, search).",
        parameters: [
          domain: [type: :string, required: false, doc: "Config domain: channels | models | search | all (default: all)"]
        ],
        module: Cortex.Tools.Handlers.GetSystemConfig
      }
    ]
  end

  def init(_config), do: {:ok, %{}}
end
