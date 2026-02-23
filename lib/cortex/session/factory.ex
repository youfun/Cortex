defmodule Cortex.Session.Factory do
  @moduledoc """
  Agent 配置工厂。集中管理 Agent 创建参数。
  """

  alias Cortex.Config.ModelSelector

  @doc """
  构建 LLMAgent 启动参数。
  """
  def build_opts(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    model = Keyword.get(opts, :model) || default_model()
    workspace_id = Keyword.get(opts, :workspace_id)

    [session_id: session_id, model: model, workspace_id: workspace_id]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  @doc """
  获取默认模型名称。
  """
  def default_model do
    case ModelSelector.default_model_info() do
      {:ok, {model_name, _id}} -> model_name
      {:error, _} -> "gemini-3-flash"
    end
  end
end
