defmodule Cortex.Runners.Runner do
  @moduledoc """
  统一执行接口。

  Runner 抽象了"给一个 prompt，拿回一个结果"的过程，
  不关心后端是 API 调用还是 CLI 进程。

  ## 实现

  - `Cortex.Runners.CLI`    — 外部 Agent CLI (gemini/claude/codex)
  - `Cortex.Runners.Native` — ReqLLM API 直接调用
  """

  @type result :: {:ok, String.t()} | {:error, term()}

  @type info :: %{
          id: String.t(),
          name: String.t(),
          type: :native | :cli,
          cost: :free | :paid
        }

  @doc "执行一次同步调用，返回完整结果"
  @callback run(prompt :: String.t(), opts :: keyword()) :: result()

  @doc "当前 runner 是否可用"
  @callback available?(opts :: keyword()) :: boolean()

  @doc "返回 runner 的元信息"
  @callback info(opts :: keyword()) :: info()
end
