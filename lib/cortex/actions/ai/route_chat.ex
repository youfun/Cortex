defmodule Cortex.Actions.AI.RouteChat do
  @moduledoc """
  统一 LLM 路由层。

  允许在运行时灵活切换不同的 LLM 提供商，而无需修改上层逻辑。
  """
  require Logger

  @required_params [:backend, :prompt]
  @valid_backends ["native"]
  @allowed_params [
    :backend,
    :model,
    :provider,
    :prompt,
    :system_prompt,
    :temperature,
    :max_tokens,
    :stream_to,
    :messages
  ]

  def run(params, context) do
    params = normalize_params(params)

    with :ok <- validate_required(params),
         :ok <- validate_backend(params) do
      case Map.get(params, :backend) do
        "native" -> run_native(params, context)
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_params(params) do
    Map.new(params, fn
      {k, v} when is_binary(k) ->
        case Cortex.Utils.SafeAtom.to_allowed(k, @allowed_params) do
          {:ok, atom} -> {atom, v}
          {:error, :not_allowed} -> {k, v}
        end

      {k, v} when is_atom(k) ->
        {k, v}
    end)
  end

  defp validate_required(params) do
    missing =
      Enum.filter(@required_params, fn key ->
        case Map.get(params, key) do
          nil -> true
          value when is_binary(value) -> String.trim(value) == ""
          _ -> false
        end
      end)

    if missing == [] do
      :ok
    else
      {:error, "缺少必需参数: #{Enum.join(missing, ", ")}"}
    end
  end

  defp validate_backend(params) do
    backend = Map.get(params, :backend)

    cond do
      backend not in @valid_backends ->
        {:error, "未知的后端类型: #{inspect(backend)}"}

      true ->
        :ok
    end
  end

  defp run_native(params, _context) do
    Logger.info("RouteChat: 使用 native 后端")

    {model_spec, req_opts} = resolve_native_model(params)
    llm_params = build_native_llm_params(params, model_spec, req_opts)

    Logger.debug(
      "RouteChat: 调用 ReqLLM.Generation.generate_text, model = #{model_spec}, opts = #{inspect(llm_params, pretty: true)}"
    )

    messages = build_native_messages(params, llm_params)
    opts = build_native_opts(llm_params)

    tools = Keyword.get(opts, :tools, [])

    Logger.debug(
      "RouteChat: tools count=#{length(tools)}, tools=#{inspect(Enum.map(tools, & &1.name))}"
    )

    generate_native(model_spec, messages, opts)
  end

  defp resolve_native_model(params) do
    model_input = Map.get(params, :model)
    model_name = model_input || "gemini-3-flash"

    case Cortex.LLM.Config.get(model_name) do
      {:ok, spec, opts} when is_binary(spec) ->
        Logger.debug("RouteChat: 解析模型配置成功: #{spec}")
        {normalize_model_spec(spec), opts}

      {:ok, spec, opts} ->
        Logger.warning(
          "RouteChat: 非预期模型 spec 类型: #{inspect(spec)}，回退为 model=#{inspect(model_name)}"
        )

        {model_name, opts}

      {:error, reason} ->
        Logger.warning("RouteChat: 解析模型配置失败 (#{inspect(reason)})，使用原始输入: #{model_input}")
        {model_name, []}
    end
  end

  defp normalize_model_spec(spec) when is_binary(spec) do
    spec = String.trim_leading(spec, ":")

    case String.split(spec, ":", parts: 3) do
      [single] -> single
      [_adapter, model] -> model
      [_adapter, model, _tier] -> model
      _ -> spec
    end
  end

  defp build_native_llm_params(params, model_spec, req_opts) do
    %{
      prompt: params.prompt,
      system_prompt: normalize_system_prompt(Map.get(params, :system_prompt)),
      model: model_spec,
      temperature: Map.get(params, :temperature, 0.7),
      max_tokens: Map.get(params, :max_tokens, 4096)
    }
    |> Map.merge(Map.new(req_opts))
  end

  defp normalize_system_prompt(system_prompt) when is_binary(system_prompt) do
    trimmed = String.trim(system_prompt)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_system_prompt(_), do: nil

  defp build_native_messages(params, llm_params) do
    history = Map.get(params, :messages)
    system_prompt = llm_params[:system_prompt]
    prompt = llm_params[:prompt]

    cond do
      is_list(history) ->
        history
        |> maybe_merge_system_prompt(system_prompt)
        |> maybe_append_user_prompt(prompt)

      is_binary(system_prompt) ->
        [
          %{role: "system", content: system_prompt},
          %{role: "user", content: prompt}
        ]

      true ->
        [%{role: "user", content: prompt}]
    end
  end

  defp maybe_merge_system_prompt(messages, nil), do: messages

  defp maybe_merge_system_prompt(messages, system_prompt) when is_list(messages) do
    {system_msgs, other_msgs} = Enum.split_with(messages, &(&1[:role] == "system"))

    if system_msgs != [] do
      combined_content =
        [system_prompt | Enum.map(system_msgs, & &1[:content])]
        |> Enum.join("\n\n")

      [%{role: "system", content: combined_content} | other_msgs]
    else
      [%{role: "system", content: system_prompt} | messages]
    end
  end

  defp maybe_append_user_prompt(messages, prompt) when is_list(messages) do
    last_msg = List.last(messages)

    if last_msg && last_msg[:role] == "user" && last_msg[:content] == prompt do
      messages
    else
      append_one(messages, %{role: "user", content: prompt})
    end
  end

  defp build_native_opts(llm_params) do
    llm_params
    |> Map.drop([:prompt, :model, :system_prompt])
    |> Map.put(:tools, Cortex.LLM.Tools.file_tools())
    |> Map.to_list()
  end

  defp append_one(list, item) do
    list
    |> Enum.reverse()
    |> then(&[item | &1])
    |> Enum.reverse()
  end

  defp generate_native(model_spec, messages, opts) do
    case ReqLLM.Generation.generate_text(model_spec, messages, opts) do
      {:ok, %ReqLLM.Response{} = response} ->
        Logger.debug(
          "RouteChat: Native LLM 调用成功, finish_reason=#{inspect(response.finish_reason)}"
        )

        result = native_response_to_result(response, model_spec)

        {:ok, normalize_response(result, "native")}

      {:error, reason} ->
        Logger.error("Native LLM 调用失败 (Reason: #{inspect(reason)})")
        {:error, reason}
    end
  end

  defp native_response_to_result(%ReqLLM.Response{} = response, model_spec) do
    tool_calls =
      response
      |> ReqLLM.Response.tool_calls()
      |> Enum.map(fn tc ->
        %{
          id: tc.id,
          name: ReqLLM.ToolCall.name(tc),
          arguments: ReqLLM.ToolCall.args_map(tc) || %{}
        }
      end)

    %{
      text: ReqLLM.Response.text(response) || "",
      tool_calls: tool_calls,
      model: model_spec,
      usage: ReqLLM.Response.usage(response) || %{}
    }
  end

  defp normalize_response(result, backend, agent_id \\ nil) do
    %{
      text: Map.get(result, :text, Map.get(result, :content, "")),
      tool_calls: Map.get(result, :tool_calls, []),
      backend: backend,
      agent_id: agent_id,
      model: Map.get(result, :model),
      usage: Map.get(result, :usage, %{})
    }
  end
end
