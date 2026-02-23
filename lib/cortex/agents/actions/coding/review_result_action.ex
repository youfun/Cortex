defmodule Cortex.Agents.CodingCoordinator.Actions.ReviewResultAction do
  @moduledoc """
  处理审查结果的 Action。

  收到 ReviewAgent 的结果后：
  1. 如果审查通过 → 完成任务
  2. 如果审查失败且未超过最大重试次数 → 重新 spawn ImplementationAgent
  3. 如果超过最大重试次数 → 标记为失败
  """

  use Jido.Action,
    name: "review_result",
    description: "处理审查结果并决定是否重试",
    schema: [
      run_id: [type: :string, required: true],
      result: [type: :map, required: true],
      passed: [type: :boolean, required: true],
      issues: [type: {:list, :map}, default: []],
      status: [type: :atom, required: true]
    ]

  require Logger
  alias Jido.Agent.Directive
  alias Cortex.Agents.Workers.ImplementationAgent

  @impl true
  def run(params, context) do
    %{run_id: run_id, result: result, passed: passed, issues: issues, status: status} = params
    state = context.state

    Logger.info(
      "[CodingCoordinator] Received review result for run_id: #{run_id}, passed: #{passed}"
    )

    if status != :success do
      # 审查过程失败
      Logger.error("[CodingCoordinator] Review process failed for run_id: #{run_id}")

      {:ok,
       %{
         phase: :failed,
         errors: append_one(state.errors, %{stage: :review, reason: "Review process failed"})
       }, []}
    else
      # 保存审查结果
      new_artifacts = Map.put(state.artifacts, :review, result)

      if passed do
        # 审查通过，任务完成
        Logger.info("[CodingCoordinator] Task completed successfully for run_id: #{run_id}")

        # 发送完成信号给 parent（如果有）
        {:ok, completion_signal} =
          Jido.Signal.new(
            "coding.task.completed",
            %{
              run_id: run_id,
              artifacts: new_artifacts,
              total_attempts: state.attempt
            },
            source: "/coordinator/coding"
          )

        emit_directive = Directive.emit_to_parent(%{state: context.state}, completion_signal)

        {:ok,
         %{
           phase: :completed,
           artifacts: new_artifacts,
           status: :success
         }, Enum.reject([emit_directive], &is_nil/1)}
      else
        # 审查未通过，检查是否可以重试
        attempt = state.attempt
        max_attempts = state.max_attempts

        if attempt < max_attempts do
          # 重试：携带失败上下文重新生成
          Logger.info(
            "[CodingCoordinator] Retrying implementation (attempt #{attempt + 1}/#{max_attempts})"
          )

          spawn_directive =
            Directive.spawn_agent(
              ImplementationAgent,
              :implementation,
              opts: %{
                run_id: run_id,
                task: state.task,
                analysis_result: state.artifacts[:analysis],
                attempt: attempt + 1,
                previous_issues: issues
              }
            )

          history_entry = %{
            attempt: attempt,
            issues: issues,
            timestamp: DateTime.utc_now()
          }

          {:ok,
           %{
             phase: :implementing,
             attempt: attempt + 1,
             artifacts: new_artifacts,
             attempt_history: append_one(state.attempt_history, history_entry)
           }, [spawn_directive]}
        else
          # 超过最大重试次数
          Logger.error("[CodingCoordinator] Max retries exceeded for run_id: #{run_id}")

          # 发送失败信号给 parent（如果有）
          {:ok, failure_signal} =
            Jido.Signal.new(
              "coding.task.failed",
              %{
                run_id: run_id,
                reason: "max_retries_exceeded",
                artifacts: new_artifacts,
                attempt_history: state.attempt_history
              },
              source: "/coordinator/coding"
            )

          emit_directive = Directive.emit_to_parent(%{state: context.state}, failure_signal)

          {:ok,
           %{
             phase: :failed,
             artifacts: new_artifacts,
             status: :max_retries_exceeded
           }, Enum.reject([emit_directive], &is_nil/1)}
        end
      end
    end
  end

  defp append_one(list, item) do
    list
    |> Enum.reverse()
    |> then(&[item | &1])
    |> Enum.reverse()
  end
end
