defmodule Cortex.LLM.Client do
  @moduledoc """
  LLM client wrapper for streaming chat requests.
  """

  require Logger

  def stream_chat(model_name, context, opts) do
    {model_spec, req_opts} = resolve_model_config(model_name)
    on_chunk = Keyword.get(opts, :on_chunk)

    # 从 Context 结构体中提取消息列表
    # ReqLLM.stream_text 期望接收消息列表，而不是 Context 结构体
    messages =
      case context do
        %ReqLLM.Context{messages: msgs} -> msgs
        msgs when is_list(msgs) -> msgs
        _ -> []
      end

    req_opts =
      opts
      |> Keyword.delete(:on_chunk)
      |> Keyword.merge(req_opts)

    Logger.debug("[LLM.Client] Streaming with model_spec: #{model_spec}")
    Logger.debug("[LLM.Client] Req options: #{inspect(Keyword.delete(req_opts, :api_key))}")
    Logger.debug("[LLM.Client] Messages count: #{length(messages)}")

    # 详细打印每条消息的结构
    messages
    |> Enum.with_index()
    |> Enum.each(fn {msg, idx} ->
      Logger.debug(
        "[LLM.Client] Message #{idx}: role=#{msg.role}, content_parts=#{length(msg.content)}"
      )

      Enum.each(msg.content, fn part ->
        Logger.debug(
          "[LLM.Client]   ContentPart type=#{part.type}, data=#{inspect(part, limit: 200)}"
        )
      end)
    end)

    case ReqLLM.stream_text(model_spec, messages, req_opts) do
      {:ok, stream_response} ->
        ReqLLM.StreamResponse.process_stream(stream_response, on_result: on_chunk)

      {:error, reason} ->
        Logger.error("[LLM.Client] stream_text failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def complete(model_name, prompt, opts \\ []) do
    {model_spec, req_opts} = resolve_model_config(model_name)
    req_opts = Keyword.merge(req_opts, opts)

    case ReqLLM.Generation.generate_text(model_spec, prompt, req_opts) do
      {:ok, response} -> {:ok, ReqLLM.Response.text(response)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_model_config(model_name) do
    case Cortex.LLM.Config.get(model_name) do
      {:ok, spec, opts} ->
        # 直接使用 spec，不要 trim，因为 ReqLLM 需要完整的 "provider:model" 格式
        {spec, opts}

      {:error, reason} ->
        Logger.warning(
          "[LLM.Client] Failed to resolve model config for #{model_name}: #{inspect(reason)}"
        )

        {model_name, []}
    end
  end
end
