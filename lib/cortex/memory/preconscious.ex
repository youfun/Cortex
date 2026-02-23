defmodule Cortex.Memory.Preconscious do
  @moduledoc """
  预意识层 —— 介于活跃意识与深度存储之间的"伸手可及"的记忆层。

  基于 Arbor Memory 的 Preconscious 模块，功能：
  - 在对话间隙分析工作记忆
  - 从长期记忆中检索可能相关的知识
  - 通过信号向意识层浮现相关记忆

  ## 工作原理

  1. 监听工作记忆更新
  2. 分析当前焦点和关注点
  3. 在知识图谱中搜索相关节点
  4. 使用扩散激活找到关联记忆
  5. 将高相关性的记忆浮现到意识层

  ## 浮现条件

  - 节点与当前焦点的关联度 > 0.5
  - 节点强度 > 0.3
  - 最近 5 分钟内未浮现过
  """

  use GenServer
  require Logger

  alias Cortex.Memory.Consolidator
  alias Cortex.Memory.KnowledgeGraph
  alias Cortex.Memory.SignalTypes
  alias Cortex.SignalHub

  @default_activation_threshold 0.5
  @min_node_strength 0.3
  @cooldown_seconds 300
  # 5 minutes

  defstruct [
    :activated_nodes,
    :last_surfaced,
    recent_activations: []
  ]

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  手动触发预意识检查。

  分析当前焦点，寻找相关记忆。
  """
  def check(focus_content, opts \\ []) do
    GenServer.call(__MODULE__, {:check, focus_content, opts})
  end

  @doc """
  获取最近激活的记忆。
  """
  def recent_activations(limit \\ 5) do
    GenServer.call(__MODULE__, {:recent_activations, limit})
  end

  @doc """
  清空激活历史。
  """
  def clear_history do
    GenServer.cast(__MODULE__, :clear_history)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # 订阅相关信号
    SignalHub.subscribe("memory.working.saved")
    SignalHub.subscribe("agent.chat.request")

    Logger.info("[Memory.Preconscious] Initialized")
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_info(%Jido.Signal{type: "agent.chat.request", data: data}, state) do
    content = payload_get(data, :content) || ""
    surfaced = perform_check(content, state)

    # 更新最近激活列表以支持冷却时间检查
    new_recent =
      surfaced
      |> Enum.map(fn {node, activation} ->
        %{
          node_id: node.id,
          content: node.content,
          activation: activation,
          timestamp: DateTime.utc_now()
        }
      end)
      |> Kernel.++(state.recent_activations)
      |> Enum.take(50)

    {:noreply, %{state | last_surfaced: surfaced, recent_activations: new_recent}}
  end

  @impl true
  def handle_info(%Jido.Signal{type: "memory.working.saved", data: data}, state) do
    # 当工作记忆更新时，触发预意识检查
    if payload_get(data, :type) == :focus do
      focus_content = payload_get(data, :content_preview) || ""
      surfaced = perform_check(focus_content, state)

      # 更新最近激活列表
      new_recent =
        surfaced
        |> Enum.map(fn {node, activation} ->
          %{
            node_id: node.id,
            content: node.content,
            activation: activation,
            timestamp: DateTime.utc_now()
          }
        end)
        |> Kernel.++(state.recent_activations)
        |> Enum.take(50)

      {:noreply, %{state | last_surfaced: surfaced, recent_activations: new_recent}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(_other, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call({:check, focus_content, _opts}, _from, state) do
    surfaced = perform_check(focus_content, state)
    {:reply, surfaced, %{state | last_surfaced: surfaced}}
  end

  @impl true
  def handle_call({:recent_activations, limit}, _from, state) do
    recent = Enum.take(state.recent_activations, limit)
    {:reply, recent, state}
  end

  @impl true
  def handle_cast(:clear_history, state) do
    {:noreply, %{state | recent_activations: [], activated_nodes: %{}}}
  end

  # Private functions

  defp perform_check(focus_content, state) do
    # 获取知识图谱
    graph = Consolidator.get_graph()

    # 搜索与焦点相关的节点
    related_nodes = KnowledgeGraph.search(graph, focus_content)

    # 获取起始节点进行扩散激活
    start_nodes = Enum.map(related_nodes, & &1.id)

    if start_nodes != [] do
      # 执行扩散激活
      activated =
        KnowledgeGraph.spreading_activation(graph, start_nodes,
          max_depth: 2,
          activation_threshold: @min_node_strength
        )

      # 过滤和排序
      surfaced =
        activated
        |> Enum.filter(fn {node, activation} ->
          activation >= @default_activation_threshold and
            node.strength >= @min_node_strength and
            not recently_surfaced?(state, node.id)
        end)
        |> Enum.take(3)

      # 发射浮现信号
      Enum.each(surfaced, fn {node, activation} ->
        emit_surfaced_memory(node, activation)
      end)

      # 更新历史
      new_activations =
        surfaced
        |> Enum.map(fn {node, activation} ->
          %{
            node_id: node.id,
            content: node.content,
            activation: activation,
            timestamp: DateTime.utc_now()
          }
        end)

      _new_state_activations = new_activations ++ state.recent_activations

      surfaced
    else
      []
    end
  end

  defp recently_surfaced?(state, node_id) do
    now = DateTime.utc_now()

    Enum.any?(state.recent_activations, fn activation ->
      activation.node_id == node_id and
        DateTime.diff(now, activation.timestamp, :second) < @cooldown_seconds
    end)
  end

  defp emit_surfaced_memory(node, activation) do
    SignalHub.emit(
      SignalTypes.memory_preconscious_surfaced(),
      %{
        provider: "memory",
        event: "preconscious",
        action: "surfaced",
        actor: "preconscious_engine",
        origin: %{channel: "memory", client: "preconscious", platform: "server"},
        node_id: node.id,
        content: node.content,
        node_type: node.type,
        activation: Float.round(activation, 2),
        strength: Float.round(node.strength, 2)
      },
      source: "/memory/preconscious"
    )
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
