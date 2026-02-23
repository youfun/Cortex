defmodule Cortex.Runners.Native do
  @moduledoc """
  Native API Runner。

  通过 ReqLLM 调用 LLM API，纯 token 消耗。

  ## Options

  - `:model`         — (必需) 模型标识，如 `"gemini-3-flash"`, `"deepseek:deepseek-chat"`
  - `:system_prompt` — 系统提示词
  - `:temperature`   — 温度参数，默认 0.7
  - `:max_tokens`    — 最大生成 token 数，默认 4096
  """

  @behaviour Cortex.Runners.Runner

  require Logger

  @impl true
  def run(prompt, opts) do
    model = Keyword.fetch!(opts, :model)
    system_prompt = Keyword.get(opts, :system_prompt)
    temperature = Keyword.get(opts, :temperature, 0.7)
    max_tokens = Keyword.get(opts, :max_tokens, 4096)

    messages = build_messages(system_prompt, prompt)

    req_opts = [
      temperature: temperature,
      max_tokens: max_tokens
    ]

    case ReqLLM.Generation.generate_text(model, messages, req_opts) do
      {:ok, %ReqLLM.Response{} = response} ->
        text = ReqLLM.Response.text(response) || ""
        {:ok, text}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def available?(_opts), do: true

  @impl true
  def info(opts) do
    model = Keyword.get(opts, :model, "unknown")

    %{
      id: model,
      name: "Native: #{model}",
      type: :native,
      cost: :paid
    }
  end

  defp build_messages(nil, prompt) do
    [%{role: "user", content: prompt}]
  end

  defp build_messages(system_prompt, prompt) do
    [
      %{role: "system", content: system_prompt},
      %{role: "user", content: prompt}
    ]
  end
end
