defmodule Cortex.Memory.Proposal do
  @moduledoc """
  潜意识提议 —— 等待意识层审批。

  基于 Arbor 提议队列的设计，用于在潜意识层分析对话后，
  向意识层提交待审核的记忆提议。

  ## 提议类型

  - `:fact` - 事实（用户偏好、项目信息等）
  - `:insight` - 洞察（发现的模式或关联）
  - `:learning` - 学习（从交互中获得的经验）
  - `:pattern` - 模式（重复出现的行为或偏好）
  - `:preference` - 偏好（用户的明确偏好）

  ## 状态

  - `:pending` - 待审核
  - `:accepted` - 已接受
  - `:rejected` - 已拒绝
  - `:deferred` - 已推迟

  ## ETS 表结构

  ETS 表 `:proposals` 存储以下记录：
  - `{:proposal, id, proposal_data}` - 提议数据
  - `{:index, :pending, id}` - 待审核提议索引
  - `{:index, :accepted, id}` - 已接受提议索引
  - `{:index, :rejected, id}` - 已拒绝提议索引
  - `{:index, :deferred, id}` - 已推迟提议索引
  - `{:counter, :total}` - 总计数器
  """

  alias __MODULE__

  @type proposal_type :: :fact | :insight | :learning | :pattern | :preference
  @type status :: :pending | :accepted | :rejected | :deferred
  @type t :: %__MODULE__{
          id: String.t(),
          agent_id: String.t(),
          type: proposal_type(),
          content: String.t(),
          confidence: float(),
          status: status(),
          source_context: map(),
          evidence: [String.t()] | [],
          created_at: DateTime.t(),
          decided_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :agent_id,
    :type,
    :content,
    :confidence,
    :status,
    :source_context,
    :created_at,
    :decided_at,
    evidence: []
  ]

  @ets_table :memory_proposals
  @default_confidence 0.5

  defp get_max_pending do
    :cortex
    |> Application.get_env(:memory, [])
    |> get_in([:thresholds, :proposal_pending_max]) || 20
  end

  # 提议类型有效性
  @valid_types [:fact, :insight, :learning, :pattern, :preference]
  @valid_statuses [:pending, :accepted, :rejected, :deferred]

  @doc """
  创建新的提议。

  ## 参数

  - `:content` - 提议内容（必需）
  - `:type` - 提议类型（默认：`:fact`）
  - `:confidence` - 置信度 0.0-1.0（默认：0.5）
  - `:agent_id` - Agent ID（默认：`"system"`）
  - `:source_context` - 来源上下文（可选）
  - `:evidence` - 证据列表（可选，默认为空列表）
  - `:created_at` - 创建时间（默认：当前 UTC 时间）
  - `:id` - 提议 ID（默认：自动生成）

  ## 示例

      iex> Proposal.new("用户偏好 Tailwind CSS", type: :fact, confidence: 0.85)
      %Proposal{content: "用户偏好 Tailwind CSS", type: :fact, confidence: 0.85, ...}
  """
  def new(content, opts \\ []) do
    type = Keyword.get(opts, :type, :fact)
    confidence = Keyword.get(opts, :confidence, @default_confidence)

    unless type in @valid_types do
      raise ArgumentError, "Invalid proposal type: #{inspect(type)}"
    end

    unless confidence >= 0.0 and confidence <= 1.0 do
      raise ArgumentError, "Confidence must be between 0.0 and 1.0"
    end

    %Proposal{
      id: Keyword.get(opts, :id, generate_id()),
      agent_id: Keyword.get(opts, :agent_id, "system"),
      type: type,
      content: content,
      confidence: confidence,
      status: :pending,
      source_context: Keyword.get(opts, :source_context, %{}),
      evidence: Keyword.get(opts, :evidence, []),
      created_at: Keyword.get(opts, :created_at, DateTime.utc_now()),
      decided_at: nil
    }
  end

  @doc """
  初始化 ETS 表。

  应该在应用启动时调用一次。
  """
  def init_ets do
    case :ets.whereis(@ets_table) do
      :undefined ->
        :ets.new(@ets_table, [
          :set,
          :public,
          :named_table,
          read_concurrency: true,
          write_concurrency: true
        ])

        # 初始化计数器
        :ets.insert(@ets_table, {:counter, :total, 0})
        :ok

      _ ->
        :ok
    end
  end

  @doc """
  创建提议并存储到 ETS。

  返回 `{:ok, proposal}` 或 `{:error, reason}`。
  """
  def create(content, opts \\ []) do
    init_ets()

    proposal = new(content, opts)

    # 存储提议数据
    :ets.insert(@ets_table, {{:proposal, proposal.id}, proposal})

    # 添加到待审核索引
    :ets.insert(@ets_table, {{:index, :pending, proposal.id}, proposal.created_at})

    # 更新计数器
    update_counter(:total, 1)

    # 强制执行每个 Agent 的 pending 上限
    enforce_pending_limit(proposal.agent_id)

    {:ok, proposal}
  end

  @doc """
  强制执行 pending 队列上限。
  如果超过 @max_pending_per_agent，自动删除最弱且最旧的提议。
  """
  def enforce_pending_limit(agent_id) do
    pending_list = list_pending(agent_id: agent_id, limit: 1000)
    max_pending = get_max_pending()

    if length(pending_list) > max_pending do
      # 淘汰策略: 先按 confidence 升序 (弱的在前), 再按 created_at 升序 (旧的在前)
      sorted =
        Enum.sort_by(pending_list, fn p ->
          {p.confidence, DateTime.to_unix(p.created_at)}
        end)

      count_to_remove = length(pending_list) - max_pending
      to_remove = Enum.take(sorted, count_to_remove)

      Enum.each(to_remove, fn p -> delete(p.id) end)
    end
  end

  @doc """
  接受提议。

  将提议状态改为 `:accepted`，并记录决定时间。
  返回 `{:ok, updated_proposal}` 或 `{:error, reason}`。
  """
  def accept(proposal_id) when is_binary(proposal_id) do
    init_ets()

    case get(proposal_id) do
      nil ->
        {:error, :not_found}

      %Proposal{} = proposal ->
        if proposal.status != :pending do
          {:error, :already_decided}
        else
          updated = %Proposal{
            proposal
            | status: :accepted,
              decided_at: DateTime.utc_now()
          }

          # 更新提议数据
          :ets.insert(@ets_table, {{:proposal, proposal_id}, updated})

          # 更新索引
          :ets.delete(@ets_table, {:index, :pending, proposal_id})
          :ets.insert(@ets_table, {{:index, :accepted, proposal_id}, updated.decided_at})

          {:ok, updated}
        end
    end
  end

  @doc """
  拒绝提议。

  将提议状态改为 `:rejected`，并记录决定时间。
  返回 `{:ok, updated_proposal}` 或 `{:error, reason}`。
  """
  def reject(proposal_id) when is_binary(proposal_id) do
    init_ets()

    case get(proposal_id) do
      nil ->
        {:error, :not_found}

      %Proposal{} = proposal ->
        if proposal.status != :pending do
          {:error, :already_decided}
        else
          updated = %Proposal{
            proposal
            | status: :rejected,
              decided_at: DateTime.utc_now()
          }

          # 更新提议数据
          :ets.insert(@ets_table, {{:proposal, proposal_id}, updated})

          # 更新索引
          :ets.delete(@ets_table, {:index, :pending, proposal_id})
          :ets.insert(@ets_table, {{:index, :rejected, proposal_id}, updated.decided_at})

          {:ok, updated}
        end
    end
  end

  @doc """
  推迟提议。

  将提议状态改为 `:deferred`，并记录决定时间。
  返回 `{:ok, updated_proposal}` 或 `{:error, reason}`。
  """
  def defer(proposal_id) when is_binary(proposal_id) do
    init_ets()

    case get(proposal_id) do
      nil ->
        {:error, :not_found}

      %Proposal{} = proposal ->
        if proposal.status != :pending do
          {:error, :already_decided}
        else
          updated = %Proposal{
            proposal
            | status: :deferred,
              decided_at: DateTime.utc_now()
          }

          # 更新提议数据
          :ets.insert(@ets_table, {{:proposal, proposal_id}, updated})

          # 更新索引
          :ets.delete(@ets_table, {:index, :pending, proposal_id})
          :ets.insert(@ets_table, {{:index, :deferred, proposal_id}, updated.decided_at})

          {:ok, updated}
        end
    end
  end

  @doc """
  根据 ID 获取提议。
  """
  def get(proposal_id) when is_binary(proposal_id) do
    init_ets()

    case :ets.lookup(@ets_table, {:proposal, proposal_id}) do
      [{{:proposal, ^proposal_id}, proposal}] -> proposal
      [] -> nil
    end
  end

  @doc """
  列出所有待审核的提议。

  ## 选项

  - `:limit` - 最大数量（默认：100）
  - `:min_confidence` - 最小置信度（默认：0.0）
  - `:order_by` - 排序方式：`:confidence`、`:time`（默认：`:time`）
  - `:agent_id` - 按 Agent ID 过滤（可选）

  ## 示例

      iex> Proposal.list_pending(limit: 10, min_confidence: 0.7)
      [%Proposal{status: :pending, confidence: 0.85, ...}, ...]
  """
  def list_pending(opts \\ []) do
    init_ets()

    limit = Keyword.get(opts, :limit, 100)
    min_confidence = Keyword.get(opts, :min_confidence, 0.0)
    order_by = Keyword.get(opts, :order_by, :time)
    agent_id_filter = Keyword.get(opts, :agent_id)

    # 获取所有待审核提议 ID
    pending_ids =
      :ets.select(@ets_table, [
        {{{:index, :pending, :"$1"}, :_}, [], [:"$1"]}
      ])

    # 获取提议数据并过滤
    proposals =
      pending_ids
      |> Enum.map(&get/1)
      |> Enum.filter(fn p ->
        p.confidence >= min_confidence and
          (is_nil(agent_id_filter) or p.agent_id == agent_id_filter)
      end)

    # 排序
    sorted =
      case order_by do
        :confidence ->
          Enum.sort_by(proposals, & &1.confidence, :desc)

        :time ->
          Enum.sort_by(proposals, &DateTime.to_unix(&1.created_at), :desc)

        _ ->
          proposals
      end

    Enum.take(sorted, limit)
  end

  @doc """
  按类型列出待审核提议。
  """
  def list_pending_by_type(type, opts \\ []) when type in @valid_types do
    opts
    |> list_pending()
    |> Enum.filter(&(&1.type == type))
  end

  @doc """
  列出所有提议（所有状态）。

  ## 选项

  - `:status` - 按状态过滤（可选）
  - `:limit` - 最大数量（默认：100）
  """
  def list_all(opts \\ []) do
    init_ets()

    limit = Keyword.get(opts, :limit, 100)
    status_filter = Keyword.get(opts, :status)

    # 获取所有提议
    proposals =
      :ets.select(@ets_table, [
        {{{:proposal, :"$1"}, :"$2"}, [], [:"$2"]}
      ])

    # 过滤和排序
    filtered =
      if status_filter do
        Enum.filter(proposals, &(&1.status == status_filter))
      else
        proposals
      end

    filtered
    |> Enum.sort_by(&DateTime.to_unix(&1.created_at), :desc)
    |> Enum.take(limit)
  end

  @doc """
  删除提议。

  返回 `:ok` 或 `{:error, :not_found}`。
  """
  def delete(proposal_id) when is_binary(proposal_id) do
    init_ets()

    case get(proposal_id) do
      nil ->
        {:error, :not_found}

      %Proposal{status: status} ->
        # 删除数据
        :ets.delete(@ets_table, {:proposal, proposal_id})

        # 删除索引
        :ets.delete(@ets_table, {:index, status, proposal_id})

        # 更新计数器
        update_counter(:total, -1)

        :ok
    end
  end

  @doc """
  获取统计信息。

  返回包含以下字段的 Map：
  - `:total` - 总提议数
  - `:pending` - 待审核数
  - `:accepted` - 已接受数
  - `:rejected` - 已拒绝数
  - `:deferred` - 已推迟数
  """
  def stats do
    init_ets()

    total = get_counter(:total)

    counts =
      Enum.reduce(@valid_statuses, %{}, fn status, acc ->
        count =
          :ets.select_count(@ets_table, [
            {{{:index, status, :_}, :_}, [], [true]}
          ])

        Map.put(acc, status, count)
      end)

    Map.merge(counts, %{total: total})
  end

  @doc """
  检查是否存在内容相似的提议（去重用）。

  使用 Jaro-Winkler 相似度检查。

  ## 参数

  - `:content` - 要检查的内容
  - `:threshold` - 相似度阈值 0.0-1.0（默认：0.8）
  - `:status` - 限制状态（默认：所有状态）

  ## 返回

  - `nil` - 没有找到相似提议
  - `%Proposal{}` - 找到的相似提议
  """
  def find_similar(content, opts \\ []) do
    init_ets()

    threshold = Keyword.get(opts, :threshold, 0.8)
    status_filter = Keyword.get(opts, :status)

    proposals =
      if status_filter do
        list_all(status: status_filter, limit: 1000)
      else
        list_all(limit: 1000)
      end

    Enum.find(proposals, fn proposal ->
      similarity = calculate_similarity(content, proposal.content)
      similarity >= threshold
    end)
  end

  @doc """
  清空所有提议数据。

  ⚠️ 危险操作，仅用于测试或重置。
  """
  def clear_all do
    init_ets()
    :ets.delete_all_objects(@ets_table)
    :ets.insert(@ets_table, {:counter, :total, 0})
    :ok
  end

  @doc """
  将提议转换为可序列化的 Map。
  """
  def to_map(%Proposal{} = proposal) do
    %{
      "id" => proposal.id,
      "agent_id" => proposal.agent_id,
      "type" => to_string(proposal.type),
      "content" => proposal.content,
      "confidence" => proposal.confidence,
      "status" => to_string(proposal.status),
      "source_context" => proposal.source_context,
      "evidence" => proposal.evidence,
      "created_at" => DateTime.to_iso8601(proposal.created_at),
      "decided_at" => if(proposal.decided_at, do: DateTime.to_iso8601(proposal.decided_at))
    }
  end

  @doc """
  从 Map 创建提议。
  """
  def from_map(map) when is_map(map) do
    %Proposal{
      id: map["id"] || generate_id(),
      agent_id: map["agent_id"] || "system",
      type: parse_type(map["type"]),
      content: map["content"] || "",
      confidence: map["confidence"] || @default_confidence,
      status: parse_status(map["status"]),
      source_context: map["source_context"] || %{},
      evidence: map["evidence"] || [],
      created_at: parse_datetime(map["created_at"]),
      decided_at: if(map["decided_at"], do: parse_datetime(map["decided_at"]))
    }
  end

  # 私有函数

  defp generate_id do
    "prop_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp update_counter(key, delta) do
    :ets.update_counter(@ets_table, {:counter, key}, delta, {{:counter, key}, 0})
  end

  defp get_counter(key) do
    case :ets.lookup(@ets_table, {:counter, key}) do
      [{{:counter, ^key}, value}] -> value
      [] -> 0
    end
  end

  defp calculate_similarity(str1, str2) do
    # 使用 Jaro 距离 (Elixir 标准库 String.jaro_distance)
    # 实际上 Elixir 的 jaro_distance 已经是比较好的相似度度量了
    String.jaro_distance(str1, str2)
  end

  defp parse_type(nil), do: :fact
  defp parse_type("fact"), do: :fact
  defp parse_type("insight"), do: :insight
  defp parse_type("learning"), do: :learning
  defp parse_type("pattern"), do: :pattern
  defp parse_type("preference"), do: :preference
  defp parse_type(type) when is_atom(type), do: type
  defp parse_type(_), do: :fact

  defp parse_status(nil), do: :pending
  defp parse_status("pending"), do: :pending
  defp parse_status("accepted"), do: :accepted
  defp parse_status("rejected"), do: :rejected
  defp parse_status("deferred"), do: :deferred
  defp parse_status(status) when is_atom(status), do: status
  defp parse_status(_), do: :pending

  defp parse_datetime(nil), do: DateTime.utc_now()

  defp parse_datetime(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, datetime, _} -> datetime
      {:error, _} -> DateTime.utc_now()
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt
  defp parse_datetime(_), do: DateTime.utc_now()
end
