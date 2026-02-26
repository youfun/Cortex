defmodule Cortex.Tools.ToolInterceptor do
  @moduledoc """
  工具级审批拦截器。
  与 ShellInterceptor 平行，拦截需要用户授权的 tool call。
  """

  @approval_required_tools ~w(update_channel_config update_model_config update_search_config)

  @doc """
  检查工具调用是否需要用户审批。

  返回值：
  - :ok - 可以直接执行
  - {:approval_required, reason} - 需要用户确认
  """
  def check(tool_name, args, ctx \\ %{})

  def check(tool_name, _args, ctx) when tool_name in @approval_required_tools do
    if tool_name in Map.get(ctx, :approved_tools, []) do
      :ok
    else
      {:approval_required, "Configuration change '#{tool_name}' requires user approval"}
    end
  end

  def check(_tool_name, _args, _ctx), do: :ok
end
