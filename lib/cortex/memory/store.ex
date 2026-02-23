defmodule Cortex.Memory.Store do
  @moduledoc """
  MemoryStore GenServer — 持久化管理。

  管理 `MEMORY.md` 读写，是记忆系统的核心存储层。

  ## 职责

  - 观察项的追加和持久化
  - 提议的接受处理（内部调用 KnowledgeGraph）
  - 记忆整合的触发
  - 操作完成后发射通知信号

  ## 通信模式

  模块内部直接调用，操作完成后发射通知信号：
  - `append_observation/1` → 直调后发射 `memory.observation.created`
  - `accept_proposal/1` → 直调后发射 `memory.kg.node_added`
  - `run_consolidation/1` → 直调后发射 `memory.consolidation.completed`

  读操作（`load_observations/1`）不发射信号。
  """

  use GenServer
  require Logger

  alias Cortex.Memory.Observation
  alias Cortex.Memory.Proposal
  alias Cortex.Memory.SignalTypes
  alias Cortex.SignalHub

  alias Cortex.Core.Security
  alias Cortex.Workspaces

  @default_memory_path "MEMORY.md"
  @max_observations 1000
  @duplicate_similarity_threshold 0.92

  defstruct [
    :workspace_root,
    :memory_path,
    observations: [],
    pending_flush: false
  ]

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  追加观察项到记忆存储。

  ## 参数

  - `observation` - %Observation{} 结构体或创建观察项的选项

  ## 示例

      Store.append_observation("用户偏好 Tailwind CSS", priority: :high)
      Store.append_observation(%Observation{...})

  ## 信号

  操作完成后发射 `memory.observation.created` 信号。
  """
  def append_observation(obs_or_content, opts_or_server \\ [])

  def append_observation(%Observation{} = observation, server) when is_atom(server) do
    GenServer.call(server, {:append_observation, observation})
  end

  def append_observation(content, opts) when is_binary(content) and is_list(opts) do
    server = Keyword.get(opts, :server, __MODULE__)
    opts = Keyword.delete(opts, :server)
    observation = Observation.new(content, opts)
    append_observation(observation, server)
  end

  @doc """
  批量追加观察项。
  """
  def append_observations(observations, server \\ __MODULE__) when is_list(observations) do
    GenServer.call(server, {:append_observations, observations})
  end

  @doc """
  接受提议并转换为观察项。

  ## 信号

  操作完成后发射：
  - `memory.proposal.accepted` - 提议已接受
  - `memory.kg.node_added` - 知识图谱节点已添加
  - `memory.observation.created` - 观察项已创建
  """
  def accept_proposal(proposal_id, server \\ __MODULE__) when is_binary(proposal_id) do
    GenServer.call(server, {:accept_proposal, proposal_id})
  end

  @doc """
  删除单条观察项。

  ## 参数

  - `observation_id` - 观察项 ID
  - `server` - GenServer 名称（默认 `__MODULE__`）

  ## 信号

  操作完成后发射 `memory.observation.deleted` 信号。
  """
  def delete_observation(observation_id, server \\ __MODULE__) when is_binary(observation_id) do
    GenServer.call(server, {:delete_observation, observation_id})
  end

  @doc """
  更新单条观察项内容。

  ## 参数

  - `observation_id` - 观察项 ID
  - `new_content` - 新内容
  - `server` - GenServer 名称（默认 `__MODULE__`）

  ## 信号

  操作完成后发射 `memory.observation.updated` 信号。
  """
  def update_observation(observation_id, new_content, server \\ __MODULE__)
      when is_binary(observation_id) and is_binary(new_content) do
    GenServer.call(server, {:update_observation, observation_id, new_content})
  end

  @doc """
  加载观察项。

  ## 选项

  - `:limit` - 最大数量（默认：100）
  - `:priority` - 按优先级过滤（可选）
  - `:since` - 只返回指定时间之后的观察项（可选）

  ## 注意

  读操作，不发射信号。
  """
  def load_observations(opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, {:load_observations, opts})
  end

  @doc """
  获取高优先级观察项摘要。

  用于注入到 System Prompt。
  """
  def get_high_priority_summary(limit \\ 10, server \\ __MODULE__) do
    load_observations(priority: :high, limit: limit, server: server)
  end

  @doc """
  运行记忆整合。

  触发衰减、剪枝等操作。

  ## 信号

  操作完成后发射 `memory.consolidation.completed` 信号。
  """
  def run_consolidation(opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, {:run_consolidation, opts})
  end

  @doc """
  清空所有观察项。

  ⚠️ 危险操作，仅用于测试。
  """
  def clear_all(server \\ __MODULE__) do
    GenServer.call(server, :clear_all)
  end

  @doc """
  获取存储统计信息。
  """
  def stats(server \\ __MODULE__) do
    GenServer.call(server, :stats)
  end

  @doc """
  强制刷新到磁盘。
  """
  def flush(server \\ __MODULE__) do
    GenServer.call(server, :flush)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    workspace_root = Keyword.get(opts, :workspace_root, Workspaces.workspace_root())
    default_path = Keyword.get(opts, :memory_path, @default_memory_path)
    memory_path = Path.join(workspace_root, default_path)

    # 集成沙箱校验
    case Security.validate_path(memory_path, workspace_root) do
      {:ok, validated_path} ->
        # 确保目录存在
        File.mkdir_p!(Path.dirname(validated_path))

        # 加载现有观察项
        observations = load_from_file(validated_path, workspace_root)

        # 启动定期刷新定时器
        schedule_flush()

        Logger.info(
          "[Memory.Store] Initialized with #{length(observations)} observations at #{validated_path}"
        )

        {:ok,
         %__MODULE__{
           workspace_root: workspace_root,
           memory_path: validated_path,
           observations: observations,
           pending_flush: false
         }}

      {:error, reason} ->
        Logger.error("[Memory.Store] Path validation failed: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:append_observation, %Observation{} = observation}, _from, state) do
    {result, new_state} = do_append_observation(state, observation)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:append_observations, observations}, _from, state) do
    new_state =
      Enum.reduce(observations, state, fn obs, acc ->
        {_res, next_acc} = do_append_observation(acc, obs)
        next_acc
      end)

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:accept_proposal, proposal_id}, _from, state) do
    case Proposal.get(proposal_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      proposal ->
        # 接受提议，允许重复接受（幂等处理）
        case Proposal.accept(proposal_id) do
          {:ok, _accepted_proposal} ->
            # 转换为观察项
            observation =
              Observation.new(proposal.content,
                priority: confidence_to_priority(proposal.confidence),
                metadata: %{
                  proposal_id: proposal.id,
                  proposal_type: proposal.type,
                  confidence: proposal.confidence
                }
              )

            # 追加到存储
            {:reply, {:ok, _}, next_state} =
              handle_call({:append_observation, observation}, nil, state)

            # 发射信号
            emit_signal(SignalTypes.memory_proposal_accepted(), %{
              proposal_id: proposal.id,
              observation_id: observation.id
            })

            emit_signal(SignalTypes.memory_kg_node_added(), %{
              node_id: observation.id,
              type: :observation,
              content: observation.content,
              content_preview: String.slice(observation.content, 0, 100)
            })

            {:reply, {:ok, observation}, %{next_state | pending_flush: true}}

          {:error, :already_decided} ->
            Logger.debug("[Memory.Store] Proposal #{proposal_id} already decided, skipping.")
            {:reply, {:ok, :already_accepted}, state}

          {:error, reason} ->
            Logger.error(
              "[Memory.Store] Failed to accept proposal #{proposal_id}: #{inspect(reason)}"
            )

            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:delete_observation, observation_id}, _from, state) do
    case Enum.find(state.observations, &(&1.id == observation_id)) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _observation ->
        new_observations = Enum.reject(state.observations, &(&1.id == observation_id))
        new_state = %{state | observations: new_observations, pending_flush: true}

        # 发射信号
        emit_signal(SignalTypes.memory_observation_deleted(), %{
          id: observation_id
        })

        Logger.info("[Memory.Store] Observation deleted: #{observation_id}")
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:update_observation, observation_id, new_content}, _from, state) do
    case Enum.find_index(state.observations, &(&1.id == observation_id)) do
      nil ->
        {:reply, {:error, :not_found}, state}

      index ->
        old_observation = Enum.at(state.observations, index)
        updated_observation = %{old_observation | content: new_content}

        new_observations = List.replace_at(state.observations, index, updated_observation)
        new_state = %{state | observations: new_observations, pending_flush: true}

        # 发射信号
        emit_signal(SignalTypes.memory_observation_updated(), %{
          id: observation_id,
          content_preview: String.slice(new_content, 0, 100)
        })

        Logger.info("[Memory.Store] Observation updated: #{observation_id}")
        {:reply, {:ok, updated_observation}, new_state}
    end
  end

  @impl true
  def handle_call({:load_observations, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 100)
    priority_filter = Keyword.get(opts, :priority)
    since = Keyword.get(opts, :since)

    observations =
      state.observations
      |> maybe_filter_by_priority(priority_filter)
      |> maybe_filter_by_time(since)
      |> Enum.sort_by(&DateTime.to_unix(&1.timestamp), :desc)
      |> Enum.take(limit)

    {:reply, observations, state}
  end

  @impl true
  def handle_call({:run_consolidation, opts}, _from, state) do
    # 执行整合操作
    # 1. 衰减旧观察项（这里简化为删除过旧的低优先级观察项）
    # 2. 限制总数
    {pruned_count, new_observations} = prune_observations(state.observations, opts)

    new_state = %{state | observations: new_observations, pending_flush: true}

    # 发射信号
    emit_signal(SignalTypes.memory_consolidation_completed(), %{
      pruned: pruned_count,
      remaining: length(new_observations),
      timestamp: DateTime.utc_now()
    })

    Logger.info(
      "[Memory.Store] Consolidation completed: pruned #{pruned_count}, remaining #{length(new_observations)}"
    )

    {:reply, {:ok, %{pruned: pruned_count, remaining: length(new_observations)}}, new_state}
  end

  @impl true
  def handle_call(:clear_all, _from, state) do
    new_state = %{state | observations: [], pending_flush: true}

    # 清空文件
    case Security.atomic_write(state.memory_path, "", state.workspace_root) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("[Memory.Store] Failed to clear memory file: #{inspect(reason)}")
    end

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      total: length(state.observations),
      by_priority: %{
        high: count_by_priority(state.observations, :high),
        medium: count_by_priority(state.observations, :medium),
        low: count_by_priority(state.observations, :low)
      },
      oldest: oldest_timestamp(state.observations),
      newest: newest_timestamp(state.observations)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    new_state = flush_to_disk(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:scheduled_flush, state) do
    new_state =
      if state.pending_flush do
        flush_to_disk(state)
      else
        state
      end

    schedule_flush()
    {:noreply, new_state}
  end

  @impl true
  def terminate(_reason, state) do
    # 确保关闭时刷新
    if state.pending_flush do
      flush_to_disk(state)
    end

    :ok
  end

  # Private Functions

  defp do_append_observation(state, %Observation{} = observation) do
    # 检查是否已存在相似观察项
    if duplicate?(state.observations, observation) do
      {{:ok, :duplicate}, state}
    else
      # 添加到内存
      new_observations = [observation | state.observations] |> trim_if_needed()

      new_state = %{state | observations: new_observations, pending_flush: true}

      # 发射信号
      emit_signal(SignalTypes.memory_observation_created(), %{
        id: observation.id,
        priority: observation.priority,
        content_preview: String.slice(observation.content, 0, 100)
      })

      Logger.info(
        "[Memory.Store] Observation stored: #{String.slice(observation.content, 0, 100)}"
      )

      {{:ok, observation}, new_state}
    end
  end

  defp load_from_file(path, project_root) do
    case Security.atomic_read(path, project_root) do
      {:ok, content} ->
        Observation.parse_markdown(content)

      {:error, :enoent} ->
        []

      {:error, reason} ->
        Logger.warning("[Memory.Store] Failed to read memory file: #{inspect(reason)}")
        []
    end
  end

  defp flush_to_disk(state) do
    content = Observation.to_markdown_full(state.observations)

    case Security.atomic_write(state.memory_path, content, state.workspace_root) do
      :ok ->
        Logger.debug("[Memory.Store] Flushed #{length(state.observations)} observations to disk")
        %{state | pending_flush: false}

      {:error, reason} ->
        Logger.error("[Memory.Store] Failed to write memory file: #{inspect(reason)}")
        state
    end
  end

  defp schedule_flush do
    # 每 30 秒刷新一次
    Process.send_after(self(), :scheduled_flush, 30_000)
  end

  defp duplicate?(existing, %Observation{} = new) do
    new_content = normalize_content(new.content)

    Enum.any?(existing, fn obs ->
      existing_content = normalize_content(obs.content)
      similarity = String.jaro_distance(existing_content, new_content)

      (obs.priority == new.priority and similarity >= @duplicate_similarity_threshold) or
        similarity >= 0.98
    end)
  end

  defp normalize_content(content) do
    content
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  defp trim_if_needed(observations) when length(observations) > @max_observations do
    # 保留最新的 @max_observations 个
    observations
    |> Enum.sort_by(&DateTime.to_unix(&1.timestamp), :desc)
    |> Enum.take(@max_observations)
  end

  defp trim_if_needed(observations), do: observations

  defp prune_observations(observations, opts) do
    max_age_days = Keyword.get(opts, :max_age_days, 30)
    cutoff_date = DateTime.add(DateTime.utc_now(), -max_age_days * 86400, :second)

    # 删除过旧的低优先级观察项
    {_pruned, kept} =
      Enum.split_with(observations, fn obs ->
        DateTime.compare(obs.timestamp, cutoff_date) == :lt and obs.priority in [:low, :medium]
      end)

    # 如果仍然超过限制，删除最旧的
    final_kept =
      if length(kept) > @max_observations do
        kept
        |> Enum.sort_by(&DateTime.to_unix(&1.timestamp), :desc)
        |> Enum.take(@max_observations)
      else
        kept
      end

    pruned_count = length(observations) - length(final_kept)
    {pruned_count, final_kept}
  end

  defp maybe_filter_by_priority(observations, nil), do: observations

  defp maybe_filter_by_priority(observations, priority) do
    Enum.filter(observations, &(&1.priority == priority))
  end

  defp maybe_filter_by_time(observations, nil), do: observations

  defp maybe_filter_by_time(observations, since) do
    Enum.filter(observations, fn obs ->
      DateTime.compare(obs.timestamp, since) != :lt
    end)
  end

  defp count_by_priority(observations, priority) do
    Enum.count(observations, &(&1.priority == priority))
  end

  defp oldest_timestamp([]), do: nil

  defp oldest_timestamp(observations) do
    observations
    |> Enum.min_by(&DateTime.to_unix(&1.timestamp))
    |> Map.get(:timestamp)
  end

  defp newest_timestamp([]), do: nil

  defp newest_timestamp(observations) do
    observations
    |> Enum.max_by(&DateTime.to_unix(&1.timestamp))
    |> Map.get(:timestamp)
  end

  defp confidence_to_priority(confidence) when confidence >= 0.8, do: :high
  defp confidence_to_priority(confidence) when confidence >= 0.5, do: :medium
  defp confidence_to_priority(_), do: :low

  defp emit_signal(type, data) do
    # 提取 event/action 信息 (根据 SignalTypes 常量)
    {event, action} =
      case type do
        "memory.observation.created" -> {"observation", "create"}
        "memory.observation.deleted" -> {"observation", "delete"}
        "memory.observation.updated" -> {"observation", "update"}
        "memory.proposal.accepted" -> {"proposal", "accept"}
        "memory.kg.node_added" -> {"kg", "node_add"}
        "memory.consolidation.completed" -> {"consolidation", "complete"}
        _ -> {"memory", "operation"}
      end

    signal_data =
      Map.merge(data, %{
        provider: "memory",
        event: event,
        action: action,
        actor: "memory_store",
        origin: %{channel: "memory", client: "memory_store", platform: "server"}
      })

    SignalHub.emit(type, signal_data, source: "/memory/store")
  end
end
