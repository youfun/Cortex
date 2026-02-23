defmodule Cortex.LLM.Config do
  @moduledoc """
  LLM 配置构建器，负责：
  - 根据 model_name 构建 ReqLLM 调用参数
  - 整合模型配置、环境变量和默认值
  """

  require Logger
  alias Cortex.Config.Metadata
  alias Cortex.Config.LlmResolver

  @doc """
  根据 model_id 或 model_name 构建 ReqLLM 调用参数

  返回：{:ok, model_spec, req_opts} | {:error, reason}
  """
  def get(model_identifier) when is_binary(model_identifier) do
    # 1. 获取模型记录
    case get_model(model_identifier) do
      {:ok, model} ->
        # 2. 使用 LlmResolver 的逻辑解析出完整的配置参数
        case LlmResolver.resolve(%{model: model.name, backend: "native"}) do
          {:ok, resolved} ->
            model_spec =
              build_model_spec(
                model.provider_drive,
                resolved.model,
                resolved.adapter
              )

            # 构建 ReqLLM 期望的选项列表
            req_opts =
              [
                api_key: resolved.api_key,
                base_url: resolved.base_url,
                temperature: resolved.temperature,
                max_tokens: resolved.max_tokens
              ]
              |> Keyword.merge(Application.get_env(:cortex, :llm_req_opts, []))

            # 合并模型记录中的 custom_overrides
            additional_opts =
              (model.custom_overrides || %{})
              |> Enum.reduce([], fn {k, v}, acc ->
                key_str = to_string(k)

                case Cortex.Utils.SafeAtom.to_existing(key_str) do
                  {:ok, atom} -> [{atom, v} | acc]
                  {:error, :not_found} -> acc
                end
              end)

            req_opts = Keyword.merge(req_opts, additional_opts)

            Logger.debug(
              "[LLM.Config] Resolved options for #{model_spec}: base_url=#{resolved.base_url}, api_key_length=#{if resolved.api_key, do: String.length(resolved.api_key), else: 0}"
            )

            {:ok, model_spec, req_opts}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :model_not_found} ->
        # Fallback to resolver defaults without DB record
        case LlmResolver.resolve(%{model: model_identifier, backend: "native"}) do
          {:ok, resolved} ->
            model_spec =
              build_model_spec(
                provider_for_adapter(resolved.adapter),
                resolved.model,
                resolved.adapter
              )

            req_opts =
              [
                api_key: resolved.api_key,
                base_url: resolved.base_url,
                temperature: resolved.temperature,
                max_tokens: resolved.max_tokens
              ]
              |> Keyword.merge(Application.get_env(:cortex, :llm_req_opts, []))

            {:ok, model_spec, req_opts}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  获取模型配置（从缓存）
  支持按 ID（UUID）或 name 查询
  """
  def get_model(identifier) do
    model =
      if is_uuid?(identifier) do
        Metadata.get_model_by_id(identifier)
      else
        nil
      end || Metadata.get_model(identifier)

    case model do
      nil -> {:error, :model_not_found}
      model -> {:ok, model}
    end
  end

  # 已废弃，因为 Provider 表已删除
  def get_provider(_provider_name), do: {:error, :provider_not_found}

  defp is_uuid?(identifier) do
    String.contains?(identifier, "-") and String.length(identifier) == 36
  end

  defp build_model_spec(provider_drive, model_name, adapter) do
    cond do
      # 如果 model_name 已经包含 :，说明已经是完整的 provider:model 格式，直接使用
      is_binary(model_name) and String.contains?(model_name, ":") ->
        model_name

      # 对于 OpenAI 兼容的服务（zenmux, openrouter, lmstudio, ollama），
      # 使用 adapter:model_name 格式（ReqLLM 标准格式）
      # 注意：model_name 可能包含 /，如 "openai/gpt-5-nano"，这是允许的
      is_binary(adapter) and adapter in ["zenmux", "openrouter", "lmstudio", "ollama", "openai"] ->
        "#{adapter}:#{model_name}"

      # 使用 provider_drive:model_name 格式（ReqLLM 标准格式）
      is_binary(provider_drive) and provider_drive != "" ->
        "#{provider_drive}:#{model_name}"

      # 使用 adapter:model_name 格式（ReqLLM 标准格式）
      is_binary(adapter) and adapter != "" ->
        "#{adapter}:#{model_name}"

      true ->
        model_name
    end
  end

  defp provider_for_adapter("gemini"), do: "google"
  defp provider_for_adapter("google"), do: "google"
  defp provider_for_adapter(adapter), do: adapter
end
