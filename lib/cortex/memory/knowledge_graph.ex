defmodule Cortex.Memory.KnowledgeGraph do
  @moduledoc """
  知识图谱 —— 语义网络存储。

  从 Arbor Memory 的 KnowledgeGraph 移植，提供：
  - 节点管理（增删改查）
  - 边管理（关系建立）
  - 衰减（decay）—— 模拟记忆遗忘
  - 强化（reinforce）—— 模拟记忆巩固
  - 剪枝（prune）—— 清理低价值节点
  - 扩散激活（spreading activation）—— 模拟联想记忆

  ## 节点类型

  - `:concept` - 概念
  - `:fact` - 事实
  - `:event` - 事件
  - `:entity` - 实体（人、物等）
  - `:preference` - 偏好

  ## 边类型

  - `:related_to` - 相关
  - `:part_of` - 组成部分
  - `:causes` - 导致
  - `:precedes` - 先于（时间）
  - `:belongs_to` - 属于
  """

  alias __MODULE__
  alias Cortex.Memory.SignalTypes
  alias Cortex.SignalHub

  require Logger

  @type node_type :: :concept | :fact | :event | :entity | :preference
  @type edge_type :: :related_to | :part_of | :causes | :precedes | :belongs_to

  defstruct [
    :name,
    nodes: %{},
    edges: %{},
    activations: %{}
  ]

  @default_decay_rate 0.05
  @default_activation_threshold 0.1
  @max_nodes 10_000

  # Node structure
  defmodule Node do
    @moduledoc "知识图谱节点"
    defstruct [
      :id,
      :type,
      :content,
      :created_at,
      :last_accessed,
      strength: 1.0,
      access_count: 0,
      metadata: %{},
      pinned: false
    ]
  end

  # Edge structure
  defmodule Edge do
    @moduledoc "知识图谱边"
    defstruct [
      :id,
      :source_id,
      :target_id,
      :type,
      :created_at,
      strength: 1.0,
      metadata: %{}
    ]
  end

  # Client API

  @doc """
  创建新的知识图谱。
  """
  def new(name \\ "default") do
    %KnowledgeGraph{name: name}
  end

  @doc """
  添加节点到知识图谱。

  ## 参数

  - `graph` - 知识图谱
  - `content` - 节点内容
  - `type` - 节点类型（默认：:fact）
  - `opts` - 可选参数
    - `:id` - 指定 ID
    - `:strength` - 初始强度（默认：1.0）
    - `:metadata` - 元数据
    - `:pinned` - 是否固定（默认：false）

  ## 信号

  操作完成后发射 `memory.kg.node_added` 信号。

  ## 返回

  `{updated_graph, node}`
  """
  def add_node(%KnowledgeGraph{} = graph, content, type \\ :fact, opts \\ []) do
    id = Keyword.get(opts, :id, generate_node_id())
    strength = Keyword.get(opts, :strength, 1.0)
    metadata = Keyword.get(opts, :metadata, %{})
    pinned = Keyword.get(opts, :pinned, false)
    now = DateTime.utc_now()

    node = %Node{
      id: id,
      type: type,
      content: content,
      created_at: now,
      last_accessed: now,
      strength: strength,
      access_count: 0,
      metadata: metadata,
      pinned: pinned
    }

    updated_graph = %KnowledgeGraph{
      graph
      | nodes: Map.put(graph.nodes, id, node)
    }

    # Emit signal
    emit_signal(SignalTypes.memory_kg_node_added(), %{
      node_id: id,
      type: type,
      content: content,
      content_preview: String.slice(content, 0, 100)
    })

    {updated_graph, node}
  end

  @doc """
  Pin 节点，防止被衰减或剪枝。
  """
  def pin_node(%KnowledgeGraph{} = graph, node_id) do
    update_node_pinned(graph, node_id, true)
  end

  @doc """
  Unpin 节点，允许被衰减或剪枝。
  """
  def unpin_node(%KnowledgeGraph{} = graph, node_id) do
    update_node_pinned(graph, node_id, false)
  end

  @doc """
  根据内容精确查找节点。
  """
  def find_by_name(%KnowledgeGraph{} = graph, content) do
    graph.nodes
    |> Map.values()
    |> Enum.find(fn node -> node.content == content end)
  end

  @doc """
  获取节点。

  如果节点存在，同时更新最后访问时间。
  """
  def get_node(%KnowledgeGraph{} = graph, node_id) do
    case Map.get(graph.nodes, node_id) do
      nil ->
        nil

      %Node{} = node ->
        # Update access info
        updated_node = %Node{
          node
          | last_accessed: DateTime.utc_now(),
            access_count: node.access_count + 1
        }

        updated_graph = %KnowledgeGraph{
          graph
          | nodes: Map.put(graph.nodes, node_id, updated_node)
        }

        {updated_graph, updated_node}
    end
  end

  @doc """
  删除节点。

  同时删除所有相关的边。
  """
  def remove_node(%KnowledgeGraph{} = graph, node_id) do
    # Remove node
    new_nodes = Map.delete(graph.nodes, node_id)

    # Remove related edges
    new_edges =
      graph.edges
      |> Enum.reject(fn {_id, edge} ->
        edge.source_id == node_id or edge.target_id == node_id
      end)
      |> Map.new()

    %KnowledgeGraph{
      graph
      | nodes: new_nodes,
        edges: new_edges
    }
  end

  @doc """
  添加边（关系）。

  ## 参数

  - `graph` - 知识图谱
  - `source_id` - 源节点 ID
  - `target_id` - 目标节点 ID
  - `type` - 边类型（默认：:related_to）
  - `opts` - 可选参数
    - `:strength` - 初始强度（默认：1.0）

  ## 信号

  操作完成后发射 `memory.kg.edge_added` 信号。

  ## 返回

  `{updated_graph, edge}`
  """
  def add_edge(%KnowledgeGraph{} = graph, source_id, target_id, type \\ :related_to, opts \\ []) do
    # Check nodes exist
    unless Map.has_key?(graph.nodes, source_id) do
      raise ArgumentError, "Source node not found: #{source_id}"
    end

    unless Map.has_key?(graph.nodes, target_id) do
      raise ArgumentError, "Target node not found: #{target_id}"
    end

    id = generate_edge_id()
    strength = Keyword.get(opts, :strength, 1.0)

    edge = %Edge{
      id: id,
      source_id: source_id,
      target_id: target_id,
      type: type,
      created_at: DateTime.utc_now(),
      strength: strength
    }

    updated_graph = %KnowledgeGraph{
      graph
      | edges: Map.put(graph.edges, id, edge)
    }

    # Emit signal
    emit_signal(SignalTypes.memory_kg_edge_added(), %{
      edge_id: id,
      source_id: source_id,
      target_id: target_id,
      type: type
    })

    {updated_graph, edge}
  end

  @doc """
  强化节点（记忆巩固）。

  增加节点强度，模拟重复暴露导致的记忆巩固。

  ## 参数

  - `amount` - 强化量（默认：0.1）
  """
  def reinforce(%KnowledgeGraph{} = graph, node_id, amount \\ 0.1) do
    case Map.get(graph.nodes, node_id) do
      nil ->
        graph

      %Node{} = node ->
        new_strength = min(node.strength + amount, 2.0)

        updated_node = %Node{
          node
          | strength: new_strength,
            last_accessed: DateTime.utc_now(),
            access_count: node.access_count + 1
        }

        %KnowledgeGraph{
          graph
          | nodes: Map.put(graph.nodes, node_id, updated_node)
        }
    end
  end

  @doc """
  衰减所有节点（记忆遗忘）。

  根据时间衰减节点强度，模拟自然遗忘过程。
  **注意：Pin 的节点不会被衰减。**

  ## 参数

  - `decay_rate` - 衰减率（默认：0.05）
  """
  def decay(%KnowledgeGraph{} = graph, decay_rate \\ @default_decay_rate) do
    now = DateTime.utc_now()

    new_nodes =
      Map.new(graph.nodes, fn {id, %Node{} = node} ->
        if node.pinned do
          {id, node}
        else
          # Calculate time-based decay
          hours_since_access =
            DateTime.diff(now, node.last_accessed, :hour)
            |> max(0)

          # Exponential decay based on time
          time_decay = :math.exp(-decay_rate * hours_since_access / 24)

          # Less decay for frequently accessed nodes
          access_bonus = min(node.access_count * 0.02, 0.5)

          new_strength = node.strength * time_decay + access_bonus

          updated_node = %Node{node | strength: max(new_strength, 0.1)}
          {id, updated_node}
        end
      end)

    %KnowledgeGraph{graph | nodes: new_nodes}
  end

  @doc """
  剪枝低强度节点。

  删除低于阈值的节点，释放空间。
  **注意：Pin 的节点不会被剪枝。**

  ## 参数

  - `threshold` - 强度阈值（默认：0.1）
  - `max_nodes` - 最大节点数（默认：10000）

  ## 信号

  操作完成后发射 `memory.kg.pruned` 信号。

  ## 返回

  `{updated_graph, pruned_count}`
  """
  def prune(
        %KnowledgeGraph{} = graph,
        threshold \\ @default_activation_threshold,
        max_nodes \\ @max_nodes
      ) do
    # Find nodes below threshold
    # Skip pinned nodes
    weak_nodes =
      graph.nodes
      |> Enum.filter(fn {_id, node} -> not node.pinned and node.strength < threshold end)
      |> Enum.map(fn {id, _} -> id end)

    # If too many nodes, also remove oldest low-access nodes
    excess_count = map_size(graph.nodes) - max_nodes

    nodes_to_prune =
      if excess_count > 0 do
        additional_nodes =
          graph.nodes
          |> Enum.reject(fn {id, node} -> node.pinned or id in weak_nodes end)
          |> Enum.sort_by(fn {_id, node} ->
            {node.access_count, DateTime.to_unix(node.last_accessed)}
          end)
          |> Enum.take(excess_count)
          |> Enum.map(fn {id, _} -> id end)

        weak_nodes ++ additional_nodes
      else
        weak_nodes
      end

    # Remove nodes and their edges
    new_graph =
      Enum.reduce(nodes_to_prune, graph, fn node_id, acc ->
        remove_node(acc, node_id)
      end)

    pruned_count = length(nodes_to_prune)

    # Emit signal if any nodes were pruned
    if pruned_count > 0 do
      emit_signal(SignalTypes.memory_kg_pruned(), %{
        pruned_count: pruned_count,
        remaining_count: map_size(new_graph.nodes),
        threshold: threshold
      })
    end

    {new_graph, pruned_count}
  end

  @doc """
  扩散激活搜索。

  从起始节点开始，通过边传播激活，找到相关节点。
  模拟人类记忆中的联想过程。

  ## 参数

  - `start_node_ids` - 起始节点 ID 列表
  - `opts` - 可选参数
    - `:max_depth` - 最大传播深度（默认：2）
    - `:activation_threshold` - 激活阈值（默认：0.1）

  ## 返回

  按激活强度排序的节点列表 `[{node, activation}]`
  """
  def spreading_activation(%KnowledgeGraph{} = graph, start_node_ids, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, 2)
    threshold = Keyword.get(opts, :activation_threshold, @default_activation_threshold)

    # Initialize activations
    initial_activations =
      start_node_ids
      |> Enum.map(fn id -> {id, 1.0} end)
      |> Map.new()

    # Propagate activation
    final_activations =
      propagate_activation(graph, initial_activations, max_depth, threshold)

    # Return sorted results
    final_activations
    |> Enum.map(fn {id, activation} ->
      node = Map.get(graph.nodes, id)
      {node, activation}
    end)
    |> Enum.reject(fn {node, _} -> is_nil(node) end)
    |> Enum.sort_by(fn {_, activation} -> activation end, :desc)
  end

  @doc """
  搜索节点。

  基于内容关键词搜索节点。
  """
  def search(%KnowledgeGraph{} = graph, query) when is_binary(query) do
    query_lower = String.downcase(query)
    query_words = String.split(query_lower, ~r/\s+/)

    graph.nodes
    |> Enum.filter(fn {_id, node} ->
      content_lower = String.downcase(node.content)

      # Check if any query word is in content
      Enum.any?(query_words, fn word ->
        String.contains?(content_lower, word)
      end)
    end)
    |> Enum.sort_by(fn {_id, node} -> node.strength end, :desc)
    |> Enum.map(fn {_id, node} -> node end)
  end

  @doc """
  获取所有节点。
  """
  def list_nodes(%KnowledgeGraph{} = graph, opts \\ []) do
    type_filter = Keyword.get(opts, :type)

    graph.nodes
    |> Map.values()
    |> maybe_filter_by_type(type_filter)
    |> Enum.sort_by(fn node -> node.strength end, :desc)
  end

  @doc """
  获取统计信息。
  """
  def stats(%KnowledgeGraph{} = graph) do
    node_count = map_size(graph.nodes)
    edge_count = map_size(graph.edges)

    avg_strength =
      if node_count > 0 do
        graph.nodes
        |> Enum.map(fn {_, node} -> node.strength end)
        |> Enum.sum()
        |> Kernel./(node_count)
      else
        0.0
      end

    by_type =
      graph.nodes
      |> Enum.group_by(fn {_, node} -> node.type end)
      |> Enum.map(fn {type, nodes} -> {type, length(nodes)} end)
      |> Map.new()

    pinned_count = Enum.count(graph.nodes, fn {_, node} -> node.pinned end)

    %{
      node_count: node_count,
      edge_count: edge_count,
      avg_strength: Float.round(avg_strength, 2),
      by_type: by_type,
      pinned_count: pinned_count
    }
  end

  @doc """
  将图谱转换为可序列化的 Map。
  """
  def to_map(%KnowledgeGraph{} = graph) do
    %{
      "name" => graph.name,
      "nodes" =>
        Map.new(graph.nodes, fn {id, node} ->
          {id,
           %{
             "id" => node.id,
             "type" => to_string(node.type),
             "content" => node.content,
             "created_at" => DateTime.to_iso8601(node.created_at),
             "last_accessed" => DateTime.to_iso8601(node.last_accessed),
             "strength" => node.strength,
             "access_count" => node.access_count,
             "metadata" => node.metadata,
             "pinned" => node.pinned
           }}
        end),
      "edges" =>
        Map.new(graph.edges, fn {id, edge} ->
          {id,
           %{
             "id" => edge.id,
             "source_id" => edge.source_id,
             "target_id" => edge.target_id,
             "type" => to_string(edge.type),
             "created_at" => DateTime.to_iso8601(edge.created_at),
             "strength" => edge.strength
           }}
        end)
    }
  end

  @doc """
  从 Map 创建图谱。
  """
  def from_map(map) when is_map(map) do
    nodes =
      Map.get(map, "nodes", %{})
      |> Enum.map(fn {id, node_map} ->
        node = %Node{
          id: node_map["id"],
          type: parse_type(node_map["type"]),
          content: node_map["content"],
          created_at: parse_datetime(node_map["created_at"]),
          last_accessed: parse_datetime(node_map["last_accessed"]),
          strength: node_map["strength"] || 1.0,
          access_count: node_map["access_count"] || 0,
          metadata: node_map["metadata"] || %{},
          pinned: node_map["pinned"] || false
        }

        {id, node}
      end)
      |> Map.new()

    edges =
      Map.get(map, "edges", %{})
      |> Enum.map(fn {id, edge_map} ->
        edge = %Edge{
          id: edge_map["id"],
          source_id: edge_map["source_id"],
          target_id: edge_map["target_id"],
          type: parse_type(edge_map["type"]),
          created_at: parse_datetime(edge_map["created_at"]),
          strength: edge_map["strength"] || 1.0
        }

        {id, edge}
      end)
      |> Map.new()

    %KnowledgeGraph{
      name: map["name"] || "default",
      nodes: nodes,
      edges: edges
    }
  end

  # Private functions

  defp update_node_pinned(%KnowledgeGraph{} = graph, node_id, pinned_status) do
    case Map.get(graph.nodes, node_id) do
      nil ->
        graph

      %Node{} = node ->
        updated_node = %Node{node | pinned: pinned_status}

        %KnowledgeGraph{
          graph
          | nodes: Map.put(graph.nodes, node_id, updated_node)
        }
    end
  end

  defp parse_type(nil), do: :fact

  @allowed_types [
    :concept,
    :fact,
    :event,
    :entity,
    :preference,
    :related_to,
    :part_of,
    :causes,
    :precedes,
    :belongs_to
  ]

  defp parse_type(type) when is_binary(type) do
    case Cortex.Utils.SafeAtom.to_allowed(type, @allowed_types) do
      {:ok, atom} -> atom
      _ -> :fact
    end
  end

  defp parse_type(type) when is_atom(type), do: type

  defp propagate_activation(_graph, activations, 0, _threshold) do
    activations
    |> Enum.filter(fn {_, activation} -> activation >= 0.01 end)
    |> Map.new()
  end

  defp propagate_activation(graph, activations, depth, threshold) do
    # Find all edges from currently activated nodes
    new_activations =
      activations
      |> Enum.flat_map(fn {node_id, activation} ->
        # Find connected edges
        graph.edges
        |> Enum.filter(fn {_id, edge} ->
          edge.source_id == node_id or edge.target_id == node_id
        end)
        |> Enum.flat_map(fn {_id, edge} ->
          neighbor_id =
            if edge.source_id == node_id do
              edge.target_id
            else
              edge.source_id
            end

          # Activation spreads with decay based on edge strength
          spread_activation = activation * edge.strength * 0.5

          if spread_activation >= threshold do
            [{neighbor_id, spread_activation}]
          else
            []
          end
        end)
      end)
      |> Enum.reduce(activations, fn {id, new_activation}, acc ->
        current = Map.get(acc, id, 0.0)
        Map.put(acc, id, max(current, new_activation))
      end)

    propagate_activation(graph, new_activations, depth - 1, threshold)
  end

  defp maybe_filter_by_type(nodes, nil), do: nodes

  defp maybe_filter_by_type(nodes, type) do
    Enum.filter(nodes, fn node -> node.type == type end)
  end

  defp generate_node_id do
    "kg_node_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp generate_edge_id do
    "kg_edge_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp parse_datetime(nil), do: DateTime.utc_now()

  defp parse_datetime(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _} -> dt
      {:error, _} -> DateTime.utc_now()
    end
  end

  defp emit_signal(type, data) do
    # 提取 event/action 信息 (根据 SignalTypes 常量)
    {event, action} =
      case type do
        "memory.kg.node_added" -> {"kg", "node_add"}
        "memory.kg.edge_added" -> {"kg", "edge_add"}
        "memory.kg.pruned" -> {"kg", "prune"}
        _ -> {"kg", "operation"}
      end

    signal_data =
      Map.merge(data, %{
        provider: "memory",
        event: event,
        action: action,
        actor: "kg_engine",
        origin: %{channel: "memory", client: "kg_engine", platform: "server"}
      })

    SignalHub.emit(type, signal_data, source: "/memory/kg")
  end
end
