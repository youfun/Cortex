defmodule Cortex.Runners.FanOut do
  @moduledoc """
  并发 Fan-Out / Fan-In 执行器。

  将同一个 prompt 发送给多个 Runner 并发执行，等待全部返回后聚合结果。
  典型场景：同一份文档发给 3 个模型评审，然后比较不同模型的答案。

  ## 使用示例

      alias Cortex.Runners.{FanOut, CLI, Native}

      reviewers = [
        %{id: "gemini",   runner: CLI,    opts: [cli: "gemini", cwd: "/path/to/project"]},
        %{id: "claude",   runner: CLI,    opts: [cli: "claude", cwd: "/path/to/project"]},
        %{id: "deepseek", runner: Native, opts: [model: "deepseek:deepseek-chat"]}
      ]

      results = FanOut.run(reviewers, "请评审这段代码...")
      # => [%FanOut.Result{id: "gemini", status: :ok, output: "...", elapsed_ms: 23400}, ...]
  """

  require Logger

  defmodule Result do
    @moduledoc "单个 Runner 的执行结果"

    @type t :: %__MODULE__{
            id: String.t(),
            status: :ok | :error | :timeout,
            output: String.t(),
            elapsed_ms: non_neg_integer()
          }

    defstruct [:id, :status, :output, :elapsed_ms]
  end

  @type reviewer :: %{
          id: String.t(),
          runner: module(),
          opts: keyword()
        }

  @default_timeout 180_000

  @doc """
  并发执行所有 reviewers，等待全部完成后返回。

  ## Options

  - `:timeout`          — 单个任务超时，默认 180_000ms
  - `:on_progress`      — 进度回调 `fn result -> :ok end`，每完成一个就调用
  - `:filter_available` — 是否自动过滤不可用的 runner，默认 true
  """
  @spec run([reviewer()], String.t(), keyword()) :: [Result.t()]
  def run(reviewers, prompt, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    on_progress = Keyword.get(opts, :on_progress)
    filter? = Keyword.get(opts, :filter_available, true)

    reviewers =
      if filter? do
        Enum.filter(reviewers, fn r -> r.runner.available?(r.opts) end)
      else
        reviewers
      end

    if Enum.empty?(reviewers) do
      Logger.warning("[FanOut] No available reviewers")
      []
    else
      ids = Enum.map(reviewers, & &1.id)
      Logger.info("[FanOut] Starting #{length(reviewers)} concurrent runners: #{inspect(ids)}")
      do_fan_out(reviewers, prompt, timeout, on_progress)
    end
  end

  # ── 内部实现 ──

  defp do_fan_out(reviewers, prompt, timeout, on_progress) do
    reviewers
    |> Task.async_stream(
      fn reviewer -> execute_one(reviewer, prompt) end,
      max_concurrency: length(reviewers),
      timeout: timeout,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Enum.map(fn
      {:ok, %Result{} = result} ->
        if on_progress, do: on_progress.(result)
        log_result(result)
        result

      {:exit, :timeout} ->
        result = %Result{
          id: "unknown",
          status: :timeout,
          output: "Task timed out",
          elapsed_ms: timeout
        }

        if on_progress, do: on_progress.(result)
        result

      {:exit, reason} ->
        exit(reason)
    end)
  end

  defp execute_one(%{id: id, runner: runner, opts: opts}, prompt) do
    start = System.monotonic_time(:millisecond)

    result = runner.run(prompt, opts)

    elapsed = System.monotonic_time(:millisecond) - start

    case result do
      {:ok, output} ->
        %Result{id: id, status: :ok, output: output, elapsed_ms: elapsed}

      {:error, reason} ->
        %Result{id: id, status: :error, output: format_error(reason), elapsed_ms: elapsed}
    end
  end

  defp log_result(%Result{status: :ok} = r) do
    Logger.info("[FanOut] ✅ #{r.id} completed in #{r.elapsed_ms}ms")
  end

  defp log_result(%Result{} = r) do
    Logger.warning(
      "[FanOut] ❌ #{r.id} #{r.status} in #{r.elapsed_ms}ms: #{String.slice(r.output, 0, 200)}"
    )
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error({:exit_code, code, output}), do: "exit #{code}: #{output}"
  defp format_error({:cli_not_found, cli}), do: "CLI not found: #{cli}"
  defp format_error(:timeout), do: "timeout"
  defp format_error(reason), do: inspect(reason, limit: 500)
end
