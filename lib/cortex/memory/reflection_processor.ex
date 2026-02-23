defmodule Cortex.Memory.ReflectionProcessor do
  @moduledoc """
  反思处理器 —— 结构化反思和洞察生成。

  基于 Arbor Memory 的 ReflectionProcessor 模块，提供：
  - **Pattern Recognition**: 从互动中识别模式
  - **Insight Generation**: 生成洞察性提议
  - **Deep Reflection**: 深度反思（周期性执行）

  ## 反思类型

  - `:daily` - 每日反思（总结当天的互动）
  - `:weekly` - 每周反思（识别周度模式）
  - `:on_demand` - 按需反思（特定触发条件）

  ## 输出

  反思结果会产生新的提议，进入提议队列等待审批。
  """

  use GenServer
  require Logger

  alias Cortex.Memory.Proposal
  alias Cortex.Memory.Store

  @default_interval_ms 24 * 60 * 60 * 1000
  # Daily

  defstruct [
    :last_reflection,
    :timer_ref,
    insights_generated: 0
  ]

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  手动触发反思。
  """
  def reflect(type \\ :on_demand) do
    GenServer.call(__MODULE__, {:reflect, type})
  end

  @doc """
  分析特定内容，生成洞察。
  """
  def analyze_content(content, opts \\ []) do
    GenServer.call(__MODULE__, {:analyze, content, opts})
  end

  @doc """
  获取反思统计。
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Schedule daily reflection
    timer_ref = schedule_reflection(@default_interval_ms)

    Logger.info("[Memory.ReflectionProcessor] Initialized")
    {:ok, %__MODULE__{timer_ref: timer_ref}}
  end

  @impl true
  def handle_call({:reflect, type}, _from, state) do
    insights = perform_reflection(type)

    new_state = %{
      state
      | last_reflection: DateTime.utc_now(),
        insights_generated: state.insights_generated + length(insights)
    }

    {:reply, {:ok, insights}, new_state}
  end

  @impl true
  def handle_call({:analyze, content, _opts}, _from, state) do
    insights = analyze_and_propose(content)

    new_state = %{
      state
      | insights_generated: state.insights_generated + length(insights)
    }

    {:reply, {:ok, insights}, new_state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      last_reflection: state.last_reflection,
      insights_generated: state.insights_generated
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:scheduled_reflection, state) do
    insights = perform_reflection(:daily)

    # Reschedule
    timer_ref = schedule_reflection(@default_interval_ms)

    new_state = %{
      state
      | timer_ref: timer_ref,
        last_reflection: DateTime.utc_now(),
        insights_generated: state.insights_generated + length(insights)
    }

    {:noreply, new_state}
  end

  # Private functions

  defp perform_reflection(:daily) do
    # Get recent observations
    since = DateTime.add(DateTime.utc_now(), -24 * 3600, :second)
    observations = Store.load_observations(since: since, limit: 100)

    # Analyze patterns
    patterns = detect_patterns(observations)

    # Generate insights
    insights =
      patterns
      |> Enum.map(fn pattern ->
        {:ok, proposal} =
          Proposal.create(pattern.description,
            type: :insight,
            confidence: pattern.confidence,
            source_context: %{
              reflection_type: :daily,
              observation_count: length(observations)
            },
            evidence: ["Daily Reflection: #{length(observations)} observations processed"]
          )

        proposal
      end)

    Logger.info(
      "[Memory.ReflectionProcessor] Daily reflection: generated #{length(insights)} insights"
    )

    insights
  end

  defp perform_reflection(:on_demand) do
    # On-demand reflection analyzes all recent observations
    observations = Store.load_observations(limit: 50)

    patterns = detect_patterns(observations)

    Enum.map(patterns, fn pattern ->
      {:ok, proposal} =
        Proposal.create(pattern.description,
          type: :insight,
          confidence: pattern.confidence,
          evidence: ["On-Demand Reflection"]
        )

      proposal
    end)
  end

  defp analyze_and_propose(content) do
    # Simple pattern analysis
    patterns = extract_patterns_from_content(content)

    Enum.map(patterns, fn {description, confidence} ->
      {:ok, proposal} =
        Proposal.create(description,
          type: :insight,
          confidence: confidence,
          evidence: ["Content Analysis: #{String.slice(content, 0, 50)}..."]
        )

      proposal
    end)
  end

  defp detect_patterns(observations) do
    # Group by priority and time
    by_priority = Enum.group_by(observations, & &1.priority)

    # Check for high priority patterns
    high_priority = Map.get(by_priority, :high, [])

    high_pattern =
      if length(high_priority) >= 3 do
        [
          %{
            description: "过去24小时内有#{length(high_priority)}个高优先级观察，建议关注重要事项",
            confidence: 0.8
          }
        ]
      else
        []
      end

    # Check for technology mentions
    tech_mentions =
      observations
      |> Enum.flat_map(fn obs ->
        techs = ["React", "Vue", "Elixir", "Python", "Docker", "Kubernetes"]
        Enum.filter(techs, &String.contains?(obs.content, &1))
      end)

    tech_pattern =
      if tech_mentions != [] do
        unique_techs = Enum.uniq(tech_mentions)

        [
          %{
            description: "用户在项目中使用了: #{Enum.join(unique_techs, ", ")}",
            confidence: 0.75
          }
        ]
      else
        []
      end

    high_pattern ++ tech_pattern
  end

  defp extract_patterns_from_content(content) do
    # Check for repeated concerns
    issue_pattern =
      if String.contains?(content, ["issue", "problem", "error", "bug"]) do
        [{"检测到可能的技术问题，建议记录解决方案", 0.6}]
      else
        []
      end

    # Check for preferences
    pref_pattern =
      if String.contains?(content, ["prefer", "like", "favorite", "best"]) do
        [{"检测到用户偏好表达，建议记录偏好", 0.7}]
      else
        []
      end

    issue_pattern ++ pref_pattern
  end

  defp schedule_reflection(interval_ms) do
    Process.send_after(self(), :scheduled_reflection, interval_ms)
  end
end
