defmodule Cortex.Extensions.Context do
  @moduledoc """
  标准化扩展上下文，传入每个 Hook/Extension 回调。
  提供 Agent 状态的只读视图 + 有限的操作 API。
  """

  @type t :: %__MODULE__{
          session_id: String.t(),
          model: String.t(),
          status: atom(),
          turn_count: non_neg_integer(),
          cwd: String.t(),
          channel: String.t(),
          token_usage: token_usage() | nil
        }

  @type token_usage :: %{
          current_tokens: non_neg_integer(),
          max_tokens: non_neg_integer(),
          percent: float()
        }

  defstruct [
    :session_id,
    :model,
    :status,
    :turn_count,
    :cwd,
    :channel,
    :token_usage
  ]

  @doc "从 LLMAgent state 构建 ExtensionContext"
  def from_agent_state(state) do
    %__MODULE__{
      session_id: state.session_id,
      model: state.config.model,
      status: state.status,
      turn_count: state.turn_count,
      cwd: Cortex.Workspaces.workspace_root(),
      channel: "agent",
      token_usage: nil
    }
  end
end
