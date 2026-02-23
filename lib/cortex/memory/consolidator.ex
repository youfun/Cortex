defmodule Cortex.Memory.Consolidator do
  @moduledoc """
  记忆整合器 —— 定时执行衰减、剪枝和归档。

  基于 Arbor Memory 的 Consolidation 模块，负责：
  - 定期衰减知识图谱中的节点
  - 剪枝低价值节点
  - 归档旧观察项
  - 触发深度反思

  ## 整合周期

  默认每 6 小时执行一次整合。
  可通过 `:consolidation_interval` 选项自定义。

  ## 信号

  - `memory.consolidation.completed` - 整合完成时发射
  """

  use GenServer
  require Logger

  alias Cortex.Memory.KnowledgeGraph
  alias Cortex.Memory.SignalTypes
  alias Cortex.Memory.Store
  alias Cortex.Core.Security
  alias Cortex.Workspaces
  alias Cortex.SignalHub

  @default_interval_ms 6 * 60 * 60 * 1000
  # 6 hours
  @min_interval_ms 60 * 1000
  # 1 minute minimum

  defstruct [
    :graph,
    :last_run,
    :interval_ms,
    :timer_ref
  ]

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  手动触发整合。
  """
  def consolidate do
    GenServer.call(__MODULE__, :consolidate)
  end

  @doc """
  更新整合间隔。

  最小间隔为 1 分钟。
  """
  def set_interval(interval_ms) when interval_ms >= @min_interval_ms do
    GenServer.cast(__MODULE__, {:set_interval, interval_ms})
  end

  @doc """
  获取当前状态统计。
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc """
  获取知识图谱。

  用于直接操作图谱（添加节点等）。
  """
  def get_graph do
    GenServer.call(__MODULE__, :get_graph)
  end

  @doc """
  更新知识图谱。
  """
  def update_graph(%KnowledgeGraph{} = graph) do
    GenServer.cast(__MODULE__, {:update_graph, graph})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    interval_ms = Keyword.get(opts, :interval_ms, @default_interval_ms)

    # 订阅记忆相关信号
    SignalHub.subscribe("memory.**")

    # 加载或创建知识图谱
    graph = load_or_create_graph()

    # 启动定时器
    timer_ref = schedule_consolidation(interval_ms)

    Logger.info("[Memory.Consolidator] Initialized with interval #{div(interval_ms, 1000)}s")

    {:ok,
     %__MODULE__{
       graph: graph,
       last_run: nil,
       interval_ms: interval_ms,
       timer_ref: timer_ref
     }}
  end

  @impl true
  def handle_call(:consolidate, _from, state) do
    {new_state, result} = perform_consolidation(state)
    {:reply, {:ok, result}, new_state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    graph_stats = KnowledgeGraph.stats(state.graph)

    stats = %{
      last_run: state.last_run,
      interval_ms: state.interval_ms,
      interval_minutes: div(state.interval_ms, 60_000),
      graph: graph_stats
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:get_graph, _from, state) do
    {:reply, state.graph, state}
  end

  @impl true
  def handle_cast({:set_interval, interval_ms}, state) do
    # 取消旧定时器
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    # 启动新定时器
    timer_ref = schedule_consolidation(interval_ms)

    {:noreply, %{state | interval_ms: interval_ms, timer_ref: timer_ref}}
  end

  @impl true
  def handle_cast({:update_graph, graph}, state) do
    {:noreply, %{state | graph: graph}}
  end

  @impl true
  def handle_info(%Jido.Signal{type: "memory.observation.created", data: data}, state) do
    # 当有新观察项时，将其作为事实节点添加到图谱
    content =
      payload_get(data, :content) || payload_get(data, :content_preview) || "New observation"

    id = payload_get(data, :id)

    {updated_graph, _node} = KnowledgeGraph.add_node(state.graph, content, :fact, id: id)

    {:noreply, %{state | graph: updated_graph}}
  end

  @impl true
  def handle_info(%Jido.Signal{type: "memory.kg.node_added", data: data}, state) do
    # 如果节点已经在图谱中（比如由上面的 observation.created 触发），add_node 会处理重复
    # 这里处理显式的节点添加信号
    id = payload_get(data, :node_id)
    type = payload_get(data, :type) || :fact
    content = payload_get(data, :content) || payload_get(data, :content_preview) || ""

    # 检查节点是否已存在
    # 即使存在，如果新的信号带有完整内容 (content)，也应该更新节点 (overwrite)
    # 这样可以确保通过 accept_proposal 带来的完整内容能覆盖 observation.created 带来的预览内容
    {updated_graph, _node} = KnowledgeGraph.add_node(state.graph, content, type, id: id)
    {:noreply, %{state | graph: updated_graph}}
  end

  @impl true
  def handle_info(:scheduled_consolidation, state) do
    {new_state, _result} = perform_consolidation(state)

    # 重新调度
    timer_ref = schedule_consolidation(state.interval_ms)

    {:noreply, %{new_state | timer_ref: timer_ref}}
  end

  @impl true
  def handle_info(_other, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # 保存图谱
    save_graph(state.graph)
    :ok
  end

  # Private functions

  defp perform_consolidation(state) do
    Logger.info("[Memory.Consolidator] Starting consolidation...")

    # 1. 衰减知识图谱节点
    decayed_graph = KnowledgeGraph.decay(state.graph, 0.05)

    # 2. 剪枝低强度节点
    {pruned_graph, pruned_count} = KnowledgeGraph.prune(decayed_graph, 0.1)

    # 3. 触发 Store 的整合
    {:ok, store_result} = Store.run_consolidation(max_age_days: 30)

    # 保存图谱
    save_graph(pruned_graph)

    # 发射信号
    emit_signal(SignalTypes.memory_consolidation_completed(), %{
      timestamp: DateTime.utc_now(),
      graph_pruned: pruned_count,
      graph_nodes: map_size(pruned_graph.nodes),
      observations_pruned: store_result.pruned,
      observations_remaining: store_result.remaining
    })

    Logger.info(
      "[Memory.Consolidator] Consolidation completed: pruned #{pruned_count} nodes, #{store_result.pruned} observations"
    )

    new_state = %{
      state
      | graph: pruned_graph,
        last_run: DateTime.utc_now()
    }

    {new_state,
     %{
       graph_pruned: pruned_count,
       observations_pruned: store_result.pruned
     }}
  end

  defp schedule_consolidation(interval_ms) do
    Process.send_after(self(), :scheduled_consolidation, interval_ms)
  end

  defp load_or_create_graph do
    path = "knowledge_graph.json"
    project_root = Workspaces.workspace_root()

    case Security.atomic_read(path, project_root) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, map} ->
            KnowledgeGraph.from_map(map)

          {:error, _} ->
            KnowledgeGraph.new()
        end

      {:error, :enoent} ->
        KnowledgeGraph.new()

      {:error, reason} ->
        Logger.warning("[Memory.Consolidator] Failed to load graph: #{inspect(reason)}")
        KnowledgeGraph.new()
    end
  end

  defp save_graph(graph) do
    path = "knowledge_graph.json"
    project_root = Workspaces.workspace_root()

    json =
      graph
      |> KnowledgeGraph.to_map()
      |> Jason.encode!(pretty: true)

    case Security.atomic_write(path, json, project_root) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("[Memory.Consolidator] Failed to save graph: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp emit_signal(type, data) do
    signal_data =
      Map.merge(data, %{
        provider: "memory",
        event: "consolidation",
        action: "complete",
        actor: "consolidator",
        origin: %{channel: "memory", client: "consolidator", platform: "server"}
      })

    SignalHub.emit(type, signal_data, source: "/memory/consolidator")
  end

  defp payload_get(data, key) when is_map(data) do
    payload =
      case data do
        %{payload: p} when is_map(p) -> p
        %{"payload" => p} when is_map(p) -> p
        _ -> %{}
      end

    Map.get(payload, key) ||
      Map.get(payload, to_string(key)) ||
      Map.get(data, key) ||
      Map.get(data, to_string(key))
  end
end
