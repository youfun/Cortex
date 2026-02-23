defmodule Cortex.Memory.BudgetEnforcer do
  @moduledoc """
  Token 预算执行器。

  在 Agent 发送请求前检查 Token 预算，自动触发压缩或拒绝请求。

  ## 使用方式

      case BudgetEnforcer.check_and_enforce(context, model_name) do
        {:ok, context} -> # 预算内，继续
        {:compacted, context} -> # 已自动压缩，继续
        {:error, :budget_exceeded} -> # 压缩后仍超预算
      end
  """

  require Logger

  alias Cortex.Agents.{Compaction, TokenCounter}
  alias Cortex.Memory.TokenBudget

  @safety_margin 0.9

  @doc """
  检查上下文是否在预算内，超预算时自动压缩。

  ## 参数
  - `context` - ReqLLM.Context 结构体
  - `model_name` - 模型名称字符串
  - `opts` - 可选参数
    - `:safety_margin` - 安全边际比例（默认 0.9）
    - `:auto_compact` - 是否自动压缩（默认 true）

  ## 返回值
  - `{:ok, context}` - 预算内，无需压缩
  - `{:compacted, context}` - 已自动压缩
  - `{:error, :budget_exceeded}` - 压缩后仍超预算
  """
  @spec check_and_enforce(ReqLLM.Context.t(), String.t(), keyword()) ::
          {:ok, ReqLLM.Context.t()}
          | {:compacted, ReqLLM.Context.t()}
          | {:error, :budget_exceeded}
  def check_and_enforce(%ReqLLM.Context{} = context, model_name, opts \\ []) do
    safety = Keyword.get(opts, :safety_margin, @safety_margin)
    auto_compact = Keyword.get(opts, :auto_compact, true)

    max_tokens = TokenBudget.get_context_size(model_name)
    budget = trunc(max_tokens * safety)
    current = TokenCounter.estimate_messages(context.messages)

    Logger.debug(
      "[BudgetEnforcer] Current: #{current} tokens, Budget: #{budget} tokens (#{trunc(safety * 100)}% of #{max_tokens})"
    )

    cond do
      current <= budget ->
        {:ok, context}

      auto_compact ->
        Logger.info(
          "[BudgetEnforcer] Budget exceeded (#{current}/#{budget}), attempting compaction"
        )

        case Compaction.maybe_compact(context, model_name) do
          {:ok, compacted_context} ->
            new_count = TokenCounter.estimate_messages(compacted_context.messages)

            if new_count <= budget do
              Logger.info(
                "[BudgetEnforcer] Compaction successful: #{current} → #{new_count} tokens"
              )

              emit_enforcement_telemetry(current, new_count, :compacted)
              {:compacted, compacted_context}
            else
              Logger.warning(
                "[BudgetEnforcer] Compaction insufficient: #{current} → #{new_count} tokens (budget: #{budget})"
              )

              emit_enforcement_telemetry(current, new_count, :exceeded)
              {:error, :budget_exceeded}
            end
        end

      true ->
        Logger.warning("[BudgetEnforcer] Budget exceeded and auto_compact disabled")
        {:error, :budget_exceeded}
    end
  end

  @doc """
  获取当前预算使用情况的快照。

  ## 参数
  - `context_or_messages` - ReqLLM.Context 或消息列表
  - `model_name` - 模型名称

  ## 返回值
  包含以下字段的 Map：
  - `:current_tokens` - 当前 Token 数
  - `:max_tokens` - 最大 Token 数
  - `:usage_ratio` - 使用比例（0.0 ~ 1.0）
  - `:remaining` - 剩余 Token 数
  - `:status` - 预算状态（:healthy | :warning | :critical | :exceeded）
  """
  @spec usage_snapshot(ReqLLM.Context.t() | [map()], String.t()) :: %{
          current_tokens: non_neg_integer(),
          max_tokens: pos_integer(),
          usage_ratio: float(),
          remaining: non_neg_integer(),
          status: :healthy | :warning | :critical | :exceeded
        }
  def usage_snapshot(context_or_messages, model_name) do
    messages = extract_messages(context_or_messages)
    max_tokens = TokenBudget.get_context_size(model_name)
    current = TokenCounter.estimate_messages(messages)

    %{
      current_tokens: current,
      max_tokens: max_tokens,
      usage_ratio: current / max(max_tokens, 1),
      remaining: max(max_tokens - current, 0),
      status: budget_status(current, max_tokens)
    }
  end

  # Private functions

  defp budget_status(current, max) do
    ratio = current / max(max, 1)

    cond do
      ratio < 0.5 -> :healthy
      ratio < 0.8 -> :warning
      ratio < 0.95 -> :critical
      true -> :exceeded
    end
  end

  defp extract_messages(%ReqLLM.Context{messages: msgs}), do: msgs
  defp extract_messages(msgs) when is_list(msgs), do: msgs

  defp emit_enforcement_telemetry(original, final, action) do
    :telemetry.execute(
      [:cortex, :budget, :enforcement],
      %{original_tokens: original, final_tokens: final},
      %{action: action}
    )
  end
end
