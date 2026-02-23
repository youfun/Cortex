defmodule Cortex.Extensions.Extension do
  @moduledoc """
  Extension behaviour。
  Extension 是代码级扩展，可注册 Hook、工具和信号处理器。
  """

  @callback init(config :: map()) :: {:ok, state :: any()} | {:error, reason :: any()}
  @callback hooks() :: [module()]
  @callback tools() :: [Cortex.Tools.Tool.t()]
  @callback name() :: String.t()
  @callback description() :: String.t()

  @optional_callbacks tools: 0, hooks: 0
end
