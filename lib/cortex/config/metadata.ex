defmodule Cortex.Config.Metadata do
  @moduledoc """
  模型元数据缓存模块，负责：
  - 使用 :persistent_term 缓存所有模型数据
  - 种子数据加载（创建初始驱动模型）
  - LLMDB 同步与合并
  """

  require Logger
  alias Cortex.Config

  @cache_key {__MODULE__, :models}

  # 标准驱动列表
  @standard_drives [
    %{id: "openai", name: "OpenAI", adapter: "openai", base_url: "https://api.openai.com/v1"},
    %{
      id: "anthropic",
      name: "Anthropic",
      adapter: "anthropic",
      base_url: "https://api.anthropic.com"
    },
    %{
      id: "google",
      name: "Google Gemini",
      adapter: "gemini",
      base_url: "https://generativelanguage.googleapis.com"
    },
    %{
      id: "local",
      name: "Local (OpenAI API)",
      adapter: "openai",
      base_url: "http://localhost:11434/v1"
    },
    %{
      id: "kimi",
      name: "Kimi (Moonshot)",
      adapter: "kimi",
      base_url: "https://api.moonshot.cn/v1"
    },
    %{
      id: "deepseek",
      name: "DeepSeek",
      adapter: "deepseek",
      base_url: "https://api.deepseek.com"
    },
    %{id: "zenmux", name: "Zenmux", adapter: "zenmux", base_url: "https://zenmux.ai/api/v1"},
    %{
      id: "openrouter",
      name: "OpenRouter",
      adapter: "openrouter",
      base_url: "https://openrouter.ai/api/v1"
    }

  ]

  def list_standard_drives, do: @standard_drives

  # ==================== 缓存管理 ====================

  def reload do
    models = Config.list_llm_models()
    :persistent_term.put(@cache_key, models)
    Logger.info("Reloaded #{length(models)} models into cache")
    :ok
  end

  def get_model_by_id(model_id) when is_binary(model_id) do
    get_all_models()
    |> Enum.find(fn model -> model.id == model_id end)
  end

  def get_model(model_name) when is_binary(model_name) do
    get_all_models()
    |> Enum.find(fn model -> model.name == model_name end)
  end

  def get_all_models do
    case :persistent_term.get(@cache_key, nil) do
      nil ->
        reload()
        :persistent_term.get(@cache_key, [])

      models ->
        models
    end
  end

  def get_available_models do
    get_all_models()
    |> Enum.filter(fn model -> model.enabled end)
  end

  # ==================== 种子数据 ====================

  @seed_models [
    %{
      name: "gemini-3-flash",
      display_name: "Gemini 3 Flash",
      provider_drive: "google",
      adapter: "gemini",
      source: "seed",
      enabled: false,
      status: "active"
    }
  ]

  @doc """
  加载初始模型种子。每个标准驱动会创建一个默认禁用的基础模型。
  """
  def load_seeds do
    Enum.each(@standard_drives, fn drive ->
      case Config.get_llm_model_by_name(drive.id) do
        nil ->
          attrs = %{
            name: drive.id,
            display_name: "#{drive.name} Default",
            provider_drive: drive.id,
            adapter: drive.adapter,
            source: "seed",
            enabled: false,
            status: "active"
          }

          Config.create_llm_model(attrs)

        _ ->
          :ok
      end
    end)

    Enum.each(@seed_models, fn model ->
      case Config.get_llm_model_by_name(model.name) do
        nil -> Config.create_llm_model(model)
        _ -> :ok
      end
    end)

    reload()
  end

  # ==================== LLMDB 同步 ====================

  def sync_from_llmdb(provider_drive, llmdb_models) when is_list(llmdb_models) do
    Logger.info(
      "[Metadata] Starting sync for drive: #{provider_drive} with #{length(llmdb_models)} models"
    )

    existing_models = Config.list_llm_models()

    Enum.each(llmdb_models, fn llmdb_model ->
      llmdb_model =
        llmdb_model
        |> Map.new(fn {k, v} -> {to_string(k), v} end)
        |> Map.put("provider_drive", provider_drive)
        |> Map.put("source", "llmdb")

      model_name = llmdb_model["name"]
      existing = Enum.find(existing_models, fn m -> m.name == model_name end)
      merged = merge_models(existing, llmdb_model)

      result =
        case existing do
          nil -> Config.create_llm_model(merged)
          model -> Config.update_llm_model(model, merged)
        end

      case result do
        {:ok, _model} ->
          :ok

        {:error, changeset} ->
          Logger.error(
            "[Metadata] Failed to sync model #{model_name}: #{inspect(changeset.errors)}"
          )
      end
    end)

    reload()
  end

  defp merge_models(nil, new_model), do: new_model

  defp merge_models(old_model, new_model) do
    if old_model.source == "custom" do
      overrides = old_model.custom_overrides || %{}
      new_model |> Map.merge(overrides) |> Map.put("source", "custom")
    else
      new_model
    end
  end
end
