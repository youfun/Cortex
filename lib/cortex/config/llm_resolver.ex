defmodule Cortex.Config.LlmResolver do
  @moduledoc """
  统一解决"从 UI/DB 配置到 LLM 调用参数"的转换。
  支持优先级读取：数据库记录 > Config (预留) > 环境变量 > 默认值。
  """
  alias Cortex.Config.LlmModel
  require Logger

  @doc """
  将 stage_config 或 default_agent_config 解析为 RouteChat 可直接使用的参数。
  """
  def resolve(config) when is_map(config) do
    config = normalize_keys(config)
    backend = Map.get(config, :backend, "native")

    case backend do
      "native" -> resolve_native(config)
      _ -> {:error, {:invalid_backend, backend}}
    end
  end

  defp resolve_native(config) do
    model_name =
      Map.get(config, :model) || Map.get(config, :llm_model_id) ||
        Cortex.Config.Settings.get_effective_skill_default_model()

    case Cortex.Config.get_llm_model_by_name(model_name) do
      %LlmModel{} = model ->
        adapter = model.adapter

        # 优先级 1: 数据库
        api_key = model.api_key
        base_url = model.base_url

        # 优先级 2: Config JSON (预留占位)
        # {api_key, base_url} = maybe_get_from_json_config(adapter, api_key, base_url)

        # 优先级 3: 环境变量
        api_key = api_key || get_env_key(adapter)
        base_url = base_url || get_env_url(adapter)

        # 优先级 4: 默认值
        base_url = base_url || get_default_url(adapter)

        {:ok,
         %{
           backend: "native",
           model: model.name,
           adapter: adapter,
           api_key: api_key,
           base_url: base_url,
           temperature: Map.get(config, :temperature, 0.7),
           max_tokens: Map.get(config, :max_tokens, 4096)
         }}

      _ ->
        # Fallback to default if model not found in DB
        {:ok,
         %{
           backend: "native",
           model: "gemini-3-flash",
           adapter: "gemini",
           api_key: get_env_key("gemini"),
           base_url: get_default_url("gemini"),
           temperature: 0.7,
           max_tokens: 4096
         }}
    end
  end



  # ==================== 配置映射辅助函数 ====================

  @env_api_keys %{
    "openai" => "OPENAI_API_KEY",
    "anthropic" => "ANTHROPIC_API_KEY",
    "google" => "GOOGLE_API_KEY",
    "gemini" => "GOOGLE_API_KEY",
    "deepseek" => "DEEPSEEK_API_KEY",
    "groq" => "GROQ_API_KEY",
    "mistral" => "MISTRAL_API_KEY",
    "xai" => "XAI_API_KEY",
    "zenmux" => "ZENMUX_API_KEY",
    "openrouter" => "OPENROUTER_API_KEY",
    "kimi" => "KIMI_API_KEY"
  }

  defp get_env_key(adapter) do
    adapter = normalize_adapter(adapter)

    case Map.get(@env_api_keys, adapter) do
      nil -> nil
      env_var -> System.get_env(env_var)
    end
  end

  defp normalize_adapter(adapter) when is_binary(adapter), do: adapter
  defp normalize_adapter(adapter) when is_atom(adapter), do: Atom.to_string(adapter)
  defp normalize_adapter(_adapter), do: nil

  def get_env_url(adapter) do
    env_var =
      case adapter do
        "openai" -> "OPENAI_BASE_URL"
        "ollama" -> "OLLAMA_BASE_URL"
        "lmstudio" -> "LMSTUDIO_BASE_URL"
        _ -> nil
      end

    if env_var, do: System.get_env(env_var), else: nil
  end

  @default_urls %{
    "openai" => "https://api.openai.com/v1",
    "anthropic" => "https://api.anthropic.com",
    "google" => "https://generativelanguage.googleapis.com",
    "gemini" => "https://generativelanguage.googleapis.com",
    "deepseek" => "https://api.deepseek.com",
    "groq" => "https://api.groq.com/otp/v1",
    "mistral" => "https://api.mistral.ai/v1",
    "xai" => "https://api.x.ai/v1",
    "ollama" => "http://localhost:11434/v1",
    "lmstudio" => "http://localhost:1234/v1",
    "zenmux" => "https://zenmux.ai/api/v1",
    "openrouter" => "https://openrouter.ai/api/v1",
    "kimi" => "https://api.moonshot.cn/v1"
  }

  def get_default_url(adapter) do
    Map.get(@default_urls, adapter)
  end

  @allowed_keys [
    :backend,
    :model,
    :llm_model_id,
    :temperature,
    :max_tokens
  ]

  defp normalize_keys(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) ->
        case Cortex.Utils.SafeAtom.to_allowed(k, @allowed_keys) do
          {:ok, atom} -> {atom, v}
          {:error, :not_allowed} -> {k, v}
        end

      {k, v} when is_atom(k) ->
        {k, v}
    end)
  end
end
