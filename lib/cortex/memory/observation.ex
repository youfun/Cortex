defmodule Cortex.Memory.Observation do
  @moduledoc """
  观察日志条目 —— 系统的短期记忆单元。

  基于 Mastra 观察日志的设计，用于记录系统运行过程中的关键观察。
  支持 Markdown 格式的序列化和解析，便于人工阅读和机器处理。

  ## 优先级图标

  - 🔴 `:high` - 高优先级
  - 🟡 `:medium` - 中优先级
  - 🟢 `:low` - 低优先级

  ## Markdown 格式示例

      # Observational Memory

      ## 2026-02-10
      🔴 14:30 用户正在构建一个 Next.js + Supabase 应用，截止日期 1 周后。
      🟡 14:35 用户倾向于使用原子化 CSS 方案，明确拒绝了 Bootstrap。

      ## 2026-02-11
      🟢 09:00 修正了 Ecto 查询中的 N+1 问题。
  """

  alias __MODULE__

  @type priority :: :high | :medium | :low
  @type t :: %__MODULE__{
          id: String.t(),
          timestamp: DateTime.t(),
          priority: priority(),
          content: String.t(),
          source_signal_id: String.t() | nil,
          metadata: map()
        }

  defstruct [
    :id,
    :timestamp,
    :priority,
    :content,
    :source_signal_id,
    metadata: %{}
  ]

  # 优先级与图标映射
  @priority_icons %{
    high: "🔴",
    medium: "🟡",
    low: "🟢"
  }

  @icon_to_priority %{
    "🔴" => :high,
    "🟡" => :medium,
    "🟢" => :low
  }

  @doc """
  创建新的观察项。

  ## 参数

  - `:content` - 观察内容（必需）
  - `:priority` - 优先级：`:high`、`:medium` 或 `:low`（默认：`:medium`）
  - `:source_signal_id` - 来源信号 ID（可选）
  - `:metadata` - 额外元数据（可选）
  - `:timestamp` - 时间戳（默认：当前 UTC 时间）
  - `:id` - 观察项 ID（默认：自动生成 UUID）

  ## 示例

      iex> Observation.new("用户偏好 Tailwind CSS", priority: :high)
      %Observation{content: "用户偏好 Tailwind CSS", priority: :high, ...}
  """
  def new(content, opts \\ []) do
    %Observation{
      id: Keyword.get(opts, :id, generate_id()),
      timestamp: Keyword.get(opts, :timestamp, DateTime.utc_now()),
      priority: Keyword.get(opts, :priority, :medium),
      content: content,
      source_signal_id: Keyword.get(opts, :source_signal_id),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  将观察项格式化为 Markdown 行。

  ## 格式

      [图标] [HH:MM] [内容]

  ## 示例

      iex> obs = Observation.new("用户偏好 Tailwind CSS", priority: :high, timestamp: ~U[2026-02-10 14:30:00Z])
      iex> Observation.to_markdown(obs)
      "🔴 14:30 用户偏好 Tailwind CSS"
  """
  def to_markdown(%Observation{} = observation) do
    icon = Map.get(@priority_icons, observation.priority, "🟡")
    time = format_time(observation.timestamp)
    "#{icon} #{time} #{observation.content}"
  end

  @doc """
  将观察项格式化为 Markdown 行（包含 ID 元数据）。

  用于需要保留完整元数据的场景。
  """
  def to_markdown_with_meta(%Observation{} = observation) do
    icon = Map.get(@priority_icons, observation.priority, "🟡")
    time = format_time(observation.timestamp)
    id = observation.id
    "#{icon} #{time} [#{id}] #{observation.content}"
  end

  @doc """
  从 Markdown 行解析观察项。

  ## 支持的格式

  - `"🔴 14:30 用户偏好 Tailwind CSS"`
  - `"🟡 09:15 [abc-123] 内容带 ID"`

  ## 参数

  - `line` - Markdown 行
  - `date` - 日期（用于构建完整时间戳，默认：今天）
  - `opts` - 可选参数
    - `:default_priority` - 无法识别图标时的默认优先级

  ## 返回

  - `{:ok, %Observation{}}` - 解析成功
  - `{:error, reason}` - 解析失败

  ## 示例

      iex> Observation.from_markdown("🔴 14:30 用户偏好 Tailwind CSS", ~D[2026-02-10])
      {:ok, %Observation{priority: :high, content: "用户偏好 Tailwind CSS", ...}}
  """
  def from_markdown(line, date \\ Date.utc_today(), opts \\ []) do
    default_priority = Keyword.get(opts, :default_priority, :medium)

    # 匹配格式：[图标] [HH:MM] [可选ID] [内容]
    # 例如：🔴 14:30 [abc-123] 用户偏好 Tailwind CSS
    # 或：🔴 14:30 用户偏好 Tailwind CSS
    regex = ~r/^([🔴🟡🟢])\s+(\d{2}:\d{2})\s+(?:\[([^\]]+)\]\s+)?(.+)$/u

    case Regex.run(regex, String.trim(line)) do
      [_, icon, time_str, id_or_nil, content] ->
        priority = Map.get(@icon_to_priority, icon, default_priority)
        timestamp = parse_timestamp(date, time_str)
        id = id_or_nil || generate_id()

        {:ok,
         %Observation{
           id: id,
           timestamp: timestamp,
           priority: priority,
           content: String.trim(content),
           source_signal_id: nil,
           metadata: %{}
         }}

      nil ->
        # 尝试更宽松的匹配（没有时间的情况）
        # 图标必须存在，以便与其他文本区分开
        loose_regex = ~r/^([🔴🟡🟢])\s*(?:\d{2}:\d{2})?\s*(?:\[([^\]]+)\]\s+)?(.+)$/u

        case Regex.run(loose_regex, String.trim(line)) do
          [_, icon, id_or_nil, content] when is_binary(content) and byte_size(content) > 0 ->
            priority =
              if icon,
                do: Map.get(@icon_to_priority, icon, default_priority),
                else: default_priority

            timestamp = DateTime.new!(date, ~T[00:00:00])
            id = id_or_nil || generate_id()

            {:ok,
             %Observation{
               id: id,
               timestamp: timestamp,
               priority: priority,
               content: String.trim(content),
               source_signal_id: nil,
               metadata: %{}
             }}

          _ ->
            {:error, "无法解析 Markdown 行格式: #{line}"}
        end
    end
  end

  @doc """
  从 Markdown 内容解析多个观察项。

  ## 参数

  - `markdown` - 完整的 Markdown 内容

  ## 返回

  观察项列表

  ## 示例

      iex> markdown = \"""
      ...> # Observational Memory
      ...>
      ...> ## 2026-02-10
      ...> 🔴 14:30 用户偏好 Tailwind CSS
      ...> 🟡 15:00 用户拒绝了 Bootstrap
      ...> \"""
      iex> Observation.parse_markdown(markdown)
      [%Observation{priority: :high, ...}, %Observation{priority: :medium, ...}]
  """
  def parse_markdown(markdown) when is_binary(markdown) do
    lines = String.split(markdown, "\n")
    current_date = Date.utc_today()

    {observations, _} =
      Enum.reduce(lines, {[], current_date}, fn line, {obs_acc, date_acc} ->
        trimmed = String.trim(line)

        cond do
          # 跳过空行和标题
          trimmed == "" ->
            {obs_acc, date_acc}

          String.starts_with?(trimmed, "# Observational Memory") ->
            {obs_acc, date_acc}

          # 日期标题
          String.starts_with?(trimmed, "## ") ->
            date_str = String.trim(String.replace_prefix(trimmed, "## ", ""))

            case Date.from_iso8601(date_str) do
              {:ok, date} -> {obs_acc, date}
              {:error, _} -> {obs_acc, date_acc}
            end

          # 观察项行
          String.starts_with?(trimmed, ["🔴", "🟡", "🟢"]) ->
            case from_markdown(trimmed, date_acc) do
              {:ok, obs} -> {[obs | obs_acc], date_acc}
              {:error, _} -> {obs_acc, date_acc}
            end

          # 其他行，跳过
          true ->
            {obs_acc, date_acc}
        end
      end)

    Enum.reverse(observations)
  end

  @doc """
  将多个观察项格式化为 Markdown 内容。

  ## 参数

  - `observations` - 观察项列表
  - `opts` - 可选参数
    - `:title` - Markdown 标题（默认："# Observational Memory"）

  ## 返回

  Markdown 字符串
  """
  def to_markdown_full(observations, opts \\ []) when is_list(observations) do
    title = Keyword.get(opts, :title, "# Observational Memory")

    # 按日期分组
    grouped =
      observations
      |> Enum.sort_by(&DateTime.to_unix(&1.timestamp), :desc)
      |> Enum.group_by(fn obs -> DateTime.to_date(obs.timestamp) end)

    if map_size(grouped) == 0 do
      title <> "\n\n"
    else
      sections =
        grouped
        |> Enum.sort_by(fn {date, _} -> Date.to_iso8601(date) end, &>=/2)
        |> Enum.map(fn {date, obs_list} ->
          date_header = "## #{Date.to_iso8601(date)}"
          lines = Enum.map(obs_list, &to_markdown/1)
          Enum.join([date_header | lines], "\n")
        end)

      Enum.join([title | sections], "\n\n") <> "\n"
    end
  end

  @doc """
  比较两个观察项是否内容相同（忽略 ID 和时间戳）。
  """
  def same_content?(%Observation{} = a, %Observation{} = b) do
    a.priority == b.priority and a.content == b.content
  end

  @doc """
  按优先级过滤观察项。
  """
  def filter_by_priority(observations, priority) when is_list(observations) do
    Enum.filter(observations, fn obs -> obs.priority == priority end)
  end

  @doc """
  获取高优先级观察项。
  """
  def high_priority(observations) when is_list(observations) do
    filter_by_priority(observations, :high)
  end

  @doc """
  按优先级排序观察项（高优先级在前）。
  """
  def sort_by_priority(observations) when is_list(observations) do
    priority_map = %{high: 0, medium: 1, low: 2}

    Enum.sort_by(observations, fn obs ->
      Map.get(priority_map, obs.priority, 99)
    end)
  end

  @doc """
  将观察项转换为可序列化的 Map。
  """
  def to_map(%Observation{} = observation) do
    %{
      "id" => observation.id,
      "timestamp" => DateTime.to_iso8601(observation.timestamp),
      "priority" => to_string(observation.priority),
      "content" => observation.content,
      "source_signal_id" => observation.source_signal_id,
      "metadata" => observation.metadata
    }
  end

  @doc """
  从 Map 创建观察项。
  """
  def from_map(map) when is_map(map) do
    %Observation{
      id:
        map[
          "id"
        ] || generate_id(),
      timestamp:
        parse_iso8601(
          map[
            "timestamp"
          ]
        ),
      priority:
        parse_priority(
          map[
            "priority"
          ]
        ),
      content:
        map[
          "content"
        ] || "",
      source_signal_id:
        map[
          "source_signal_id"
        ],
      metadata:
        map[
          "metadata"
        ] || %{}
    }
  end

  # 私有函数

  defp generate_id do
    "obs_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp format_time(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_time()
    |> Time.truncate(:second)
    |> Time.to_iso8601()
    |> String.slice(0, 5)
  end

  defp parse_timestamp(date, time_str) do
    case Time.from_iso8601(time_str <> ":00") do
      {:ok, time} ->
        DateTime.new!(date, time)

      {:error, _} ->
        DateTime.new!(date, ~T[00:00:00])
    end
  end

  defp parse_iso8601(nil), do: DateTime.utc_now()

  defp parse_iso8601(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, datetime, _} -> datetime
      {:error, _} -> DateTime.utc_now()
    end
  end

  defp parse_iso8601(%DateTime{} = datetime), do: datetime
  defp parse_iso8601(_), do: DateTime.utc_now()

  defp parse_priority(nil), do: :medium
  defp parse_priority("high"), do: :high
  defp parse_priority("medium"), do: :medium
  defp parse_priority("low"), do: :low
  defp parse_priority(:high), do: :high
  defp parse_priority(:medium), do: :medium
  defp parse_priority(:low), do: :low
  defp parse_priority(_), do: :medium
end
