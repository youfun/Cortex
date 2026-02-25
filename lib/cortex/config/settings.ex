defmodule Cortex.Config.Settings do
  @moduledoc """
  全局设置管理模块，负责：
  - 默认模型配置
  - Model 的启用/禁用管理
  """

  import Ecto.Query
  alias Cortex.Repo
  alias Cortex.Config
  alias Cortex.Config.LlmModel

  @default_settings %{
    "skill_default_model" => "gemini-3-flash",
    "arena_primary_model" => nil,
    "arena_secondary_model" => nil,
    "title_generation" => "disabled",
    "title_model" => nil
  }

  # ==================== 默认模型管理 ====================

  def get_effective_skill_default_model do
    get_valid_skill_default_model() ||
      first_enabled_model() ||
      get_skill_default_model() ||
      @default_settings["skill_default_model"]
  end

  def get_skill_default_model do
    case get_global_setting("skill_default_model") do
      nil -> @default_settings["skill_default_model"]
      value -> value
    end
  end

  def set_skill_default_model(model_name) when is_binary(model_name) do
    set_global_setting("skill_default_model", model_name)
  end

  # ==================== Model 管理 ====================

  def enable_model(model_name) when is_binary(model_name) do
    case Config.get_llm_model_by_name(model_name) do
      nil -> {:error, :not_found}
      model -> Config.update_llm_model(model, %{enabled: true})
    end
  end

  def disable_model(model_name) when is_binary(model_name) do
    case Config.get_llm_model_by_name(model_name) do
      nil -> {:error, :not_found}
      model -> Config.update_llm_model(model, %{enabled: false})
    end
  end

  def model_available?(model_name) when is_binary(model_name) do
    case Config.get_llm_model_by_name(model_name) do
      nil -> false
      %LlmModel{enabled: true} -> true
      _ -> false
    end
  end

  def list_available_models do
    LlmModel
    |> where([m], m.enabled == true)
    |> Repo.all()
  end

  # ==================== 私有辅助函数 ====================

  defp get_valid_skill_default_model do
    model_name = get_skill_default_model()

    if model_name && model_available?(model_name) do
      model_name
    else
      nil
    end
  end

  defp first_enabled_model do
    case list_available_models() do
      [] -> nil
      [model | _] -> model.name
    end
  end

  defp get_global_setting(key) do
    case :persistent_term.get({__MODULE__, key}, nil) do
      nil -> nil
      value -> value
    end
  end

  defp set_global_setting(key, value) do
    :persistent_term.put({__MODULE__, key}, value)
    {:ok, value}
  end

  # ==================== 标题生成配置 ====================

  def get_title_generation do
    get_global_setting("title_generation") || @default_settings["title_generation"]
  end

  def get_title_model do
    get_global_setting("title_model")
  end

  def set_title_generation(mode) when mode in ["disabled", "conversation", "model"] do
    set_global_setting("title_generation", mode)
  end

  def set_title_model(model_name) when is_binary(model_name) do
    set_global_setting("title_model", model_name)
  end
end
