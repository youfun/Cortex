defmodule Cortex.Agents.HookRunner do
  @moduledoc """
  Runs a series of hooks for a given stage.

  支持三种运行模式：
  - `run/4` — 拦截模式：{:ok, ...} 继续, {:halt, ...} 中断
  - `run_filter/4` — 过滤模式：链式修改数据，每个 hook 的输出是下一个的输入
  - `run_notify/3` — 通知模式：所有 hook 都执行，不可中断
  """
  require Logger

  @doc """
  拦截模式运行 hooks。支持新的返回值语义。
  """
  def run(hooks, stage, agent_state, data) do
    Enum.reduce_while(hooks, {:ok, data, agent_state}, fn hook,
                                                          {_status, current_data, current_state} ->
      Code.ensure_loaded(hook)

      if function_exported?(hook, stage, 2) do
        result = apply(hook, stage, [current_state, current_data])
        handle_result(result, current_data, current_state, hook, stage)
      else
        {:cont, {:ok, current_data, current_state}}
      end
    end)
  end

  @doc """
  过滤模式：链式修改数据。用于 on_context 等需要多个 hook 依次修改数据的场景。
  """
  def run_filter(hooks, stage, agent_state, data) do
    Enum.reduce(hooks, data, fn hook, current_data ->
      Code.ensure_loaded(hook)

      if function_exported?(hook, stage, 2) do
        case apply(hook, stage, [agent_state, current_data]) do
          {:ok, new_data, _new_state} -> new_data
          {:pass, _reason, _new_state} -> current_data
          _ -> current_data
        end
      else
        current_data
      end
    end)
  end

  @doc """
  通知模式：所有 hook 都执行，不可中断。用于 on_agent_end 等通知型事件。
  """
  def run_notify(hooks, stage, agent_state) do
    Enum.each(hooks, fn hook ->
      Code.ensure_loaded(hook)

      if function_exported?(hook, stage, 1) do
        apply(hook, stage, [agent_state])
      end
    end)
  end

  # 内部辅助

  defp handle_result(result, current_data, current_state, hook, stage) do
    case result do
      {:ok, new_data, new_state} ->
        {:cont, {:ok, new_data, new_state}}

      {:halt, reason, new_state} ->
        {:halt, {:halt, reason, new_state}}

      {:continue, new_data, new_state} ->
        {:cont, {:ok, new_data, new_state}}

      {:transform, new_data, new_state} ->
        {:cont, {:ok, new_data, new_state}}

      {:handled, response, new_state} ->
        {:halt, {:handled, response, new_state}}

      {:pass, _reason, new_state} ->
        {:cont, {:ok, current_data, new_state}}

      {:cancel, reason, new_state} ->
        {:halt, {:cancel, reason, new_state}}

      {:custom, custom_data, new_state} ->
        {:halt, {:custom, custom_data, new_state}}

      other ->
        Logger.warning(
          "Hook #{inspect(hook)} returned invalid result for #{stage}: #{inspect(other)}"
        )

        {:cont, {:ok, current_data, current_state}}
    end
  end
end
