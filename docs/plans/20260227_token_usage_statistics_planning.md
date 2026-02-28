# Token 消耗统计工具规划

**日期**: 2026-02-27  
**参考**: 搜索能力规划 (Extension 化), Gong TokenEstimator, Arbor TokenBudget

---

## 核心决策

- 以 **Extension 插件**形式集成，通过 `ConfigExtension` 注册工具
- 统计数据存储在 **数据库**（新建 `token_usage_logs` 表）
- 支持 **LLM 工具调用**查询统计数据（按会话、按模型、按时间范围）
- **需要在 `AgentLoop` 中提取 `ReqLLM.Response.usage/1` 并添加到 `agent.response` 信号**
- 提供 **UI 界面**展示统计图表（新增 `/settings/usage` 页面，使用纯 SVG 渲染）

## ⚠️ 重要修正

### 1. 信号结构修正
根据实际代码分析，`agent.response` 信号的结构为：
- **顶层固定字段**：`provider`, `event`, `action`, `actor`, `origin`（必需）
- **payload 字段**：其他所有业务数据（如 `session_id`, `conversation_id`, `model_name`, `content`, `usage`）会被 `SignalHub.normalize_data/1` 自动移入 `payload` 中
- **当前缺失**：`usage` 字段（需要在 `AgentLoop` 中补充）

**关键发现：**
- `SignalHub.emit/3` 会自动将非固定字段（除 `provider/event/action/actor/origin/payload` 外）移入 `payload`
- **`origin` 保留在顶层**（`signal.data.origin`），因为它是必需的固定字段
- 因此 `Collector` 应该：
  - 从 `signal.data.payload` 中提取 `usage`, `session_id`, `model_name`, `conversation_id` 等
  - 从 `signal.data.origin` 中提取 `channel`（origin 在顶层，不在 payload 里）
  - 从 `signal.data.provider` 中提取 `provider`（固定字段，在顶层）

### 2. 数据降级策略
- `model` 字段改为**可空**（允许 `nil`），默认值为 `"unknown"`
- **`session_id` 策略调整**：
  - **数据库字段**：改为 `null: false`（不允许空值）
  - **Collector 行为**：缺少 `session_id` 时跳过记录，记录 warning 日志
  - **Fallback 逻辑**：优先使用 `payload.session_id`，若为空则尝试 `origin.session_id`
  - **理由**：`session_id` 是统计的核心维度，缺失时无法关联到具体会话，允许空值会导致"孤儿数据"无法被查询利用
- **`total_tokens == 0` 策略**：
  - **Collector 校验**：`total_tokens <= 0` 时跳过记录，记录 debug 日志
  - **Schema 校验**：`validate_number(:total_tokens, greater_than: 0)`
  - **理由**：`total_tokens == 0` 通常表示异常响应或空响应，记录这些数据会污染统计结果；如需排查问题，应查看 Agent 日志而非 usage 统计
- 插入失败时只记录日志，不抛异常，确保不影响 Agent 主流程

### 3. UI 渲染方案
- **不使用 Chart.js**（项目未引入，避免增加依赖）
- 改用 **LiveView 原生 SVG** 或 **纯 CSS 渲染**（柱状图、折线图）
- 参考 Phoenix LiveView 的 `Phoenix.LiveView.JS` 和 Tailwind CSS 实现轻量图表

---

## 架构分层

```
Agent (LLM Response) → RouteChat.usage
    │
    ▼
Cortex.Usage.Collector                   ← 监听 agent.response 信号，记录 usage
    │
    ▼
Cortex.Usage.Store (DB)                  ← 持久化到 token_usage_logs 表
    │
    ▼
Cortex.Tools.Handlers.GetTokenUsage      ← LLM 工具：查询统计数据
Cortex.Tools.Handlers.ResetTokenUsage    ← LLM 工具：重置统计（需审批）
    │
    ▼
CortexWeb.SettingsLive.UsageComponent    ← UI：图表展示
```

---

## 文件结构

```
lib/cortex/
├── usage/
│   ├── collector.ex                     # GenServer，监听 agent.response 信号
│   ├── store.ex                         # 数据库操作（插入、查询、聚合）
│   └── schema.ex                        # Ecto schema: token_usage_logs
├── tools/handlers/
│   ├── get_token_usage.ex               # 查询统计工具
│   └── reset_token_usage.ex             # 重置统计工具（高风险）
└── extensions/
    └── config_extension.ex              # 已存在，添加 2 个新工具

lib/cortex_web/live/settings_live/
└── usage_component.ex                   # 新建 LiveView 组件

priv/repo/migrations/
└── YYYYMMDDHHMMSS_create_token_usage_logs.exs

test/cortex/usage/
├── collector_test.exs
└── store_test.exs
```

---

## 数据模型

### Schema: `token_usage_logs`

```elixir
defmodule Cortex.Usage.Schema do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "token_usage_logs" do
    field :session_id, :string              # 会话 ID（必需，核心维度）
    field :conversation_id, :binary_id      # 关联 conversations 表
    field :model, :string                   # 模型名称（可空，默认 "unknown"）
    field :provider, :string                # 提供商（如 "google", "anthropic"）
    
    # Token 统计（来自 ReqLLM.Response.usage）
    field :prompt_tokens, :integer          # 输入 tokens
    field :completion_tokens, :integer      # 输出 tokens
    field :total_tokens, :integer           # 总计 tokens
    
    # 元数据
    field :channel, :string                 # 来源通道（ui, telegram, feishu）
    field :turn_count, :integer             # 对话轮次
    field :has_tool_calls, :boolean         # 是否包含工具调用
    
    timestamps()                            # inserted_at, updated_at
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :session_id, :conversation_id, :model, :provider,
      :prompt_tokens, :completion_tokens, :total_tokens,
      :channel, :turn_count, :has_tool_calls
    ])
    |> validate_required([:session_id, :total_tokens])
    |> validate_number(:total_tokens, greater_than: 0)
    |> put_default_model()
  end

  defp put_default_model(changeset) do
    case get_field(changeset, :model) do
      nil -> put_change(changeset, :model, "unknown")
      _ -> changeset
    end
  end
end
```

### Migration

```elixir
defmodule Cortex.Repo.Migrations.CreateTokenUsageLogs do
  use Ecto.Migration

  def change do
    create table(:token_usage_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :session_id, :string, null: false     # 修正：不允许空值，核心维度
      add :conversation_id, :binary_id
      add :model, :string, default: "unknown"   # 可空，默认 "unknown"
      add :provider, :string
      
      add :prompt_tokens, :integer, default: 0
      add :completion_tokens, :integer, default: 0
      add :total_tokens, :integer, default: 0, null: false
      
      add :channel, :string
      add :turn_count, :integer
      add :has_tool_calls, :boolean, default: false
      
      timestamps()
    end

    create index(:token_usage_logs, [:session_id])
    create index(:token_usage_logs, [:conversation_id])
    create index(:token_usage_logs, [:model])
    create index(:token_usage_logs, [:inserted_at])
  end
end
```

---

## 核心组件

### 1. Usage.Collector (信号监听器)

```elixir
defmodule Cortex.Usage.Collector do
  @moduledoc """
  监听 agent.response 信号，提取 usage 数据并持久化。
  """
  use GenServer
  require Logger

  alias Cortex.Usage.Store
  alias Cortex.SignalHub

  def start_link(opts \\\\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    SignalHub.subscribe("agent.response")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:signal, %Jido.Signal{type: "agent.response"} = signal}, state) do
    extract_and_store_usage(signal)
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp extract_and_store_usage(signal) do
    # 修正：从 signal.data.payload 提取元数据
    with {:ok, usage} <- extract_usage(signal),
         {:ok, metadata} <- extract_metadata(signal),
         :ok <- Store.record_usage(usage, metadata) do
      Logger.debug("[Usage.Collector] Recorded usage: #{inspect(usage)}")
    else
      {:error, :no_usage_data} ->
        # 降级：没有 usage 数据时只记录 debug 日志
        Logger.debug("[Usage.Collector] No usage data in signal: #{signal.type}")

      {:error, :missing_session_id} ->
        # 降级：缺少 session_id 时跳过记录
        Logger.warning("[Usage.Collector] Missing session_id, skipping record")

      {:error, :invalid_usage_data} ->
        # 降级：usage 数据无效（total_tokens <= 0）
        Logger.debug("[Usage.Collector] Invalid usage data (total_tokens <= 0), skipping record")

      {:error, reason} ->
        Logger.warning("[Usage.Collector] Failed to record: #{inspect(reason)}")
    end
  end

  defp extract_usage(%Jido.Signal{data: data} = _signal) do
    # 修正：usage 在 data.payload 里，而非顶层
    payload = Map.get(data, :payload, %{})
    
    case Map.get(payload, :usage) do
      nil ->
        {:error, :no_usage_data}

      usage when is_map(usage) ->
        # 修正：增强校验，确保 usage 数据有效
        prompt_tokens = Map.get(usage, :prompt_tokens, 0)
        completion_tokens = Map.get(usage, :completion_tokens, 0)
        total_tokens = Map.get(usage, :total_tokens, 0)

        # 校验：total_tokens 必须大于 0
        if total_tokens > 0 do
          {:ok, %{
            prompt_tokens: prompt_tokens,
            completion_tokens: completion_tokens,
            total_tokens: total_tokens
          }}
        else
          {:error, :invalid_usage_data}
        end

      _ ->
        {:error, :invalid_usage_format}
    end
  end

  defp extract_metadata(%Jido.Signal{data: data} = signal) do
    # 修正：业务字段在 data.payload 里，origin 在 data 顶层
    payload = Map.get(data, :payload, %{})
    origin = Map.get(data, :origin, %{})
    
    # 修正：增加 fallback 逻辑，优先使用 payload.session_id，若为空则尝试 origin.session_id
    session_id = Map.get(payload, :session_id) || Map.get(origin, :session_id)

    # 降级：session_id 为空时返回错误
    if is_nil(session_id) or session_id == "" do
      {:error, :missing_session_id}
    else
      {:ok, %{
        session_id: session_id,
        conversation_id: Map.get(payload, :conversation_id),
        model: Map.get(payload, :model_name) || Map.get(payload, :model),
        provider: extract_provider(data),
        channel: Map.get(origin, :channel),
        turn_count: Map.get(payload, :turn_count),
        has_tool_calls: has_tool_calls?(payload)
      }}
    end
  end

  defp extract_provider(%{provider: provider}) when is_binary(provider) do
    # 修正：优先使用顶层 provider 字段（固定字段）
    provider
  end
  
  defp extract_provider(data) do
    # Fallback：从 model 名称猜测
    payload = Map.get(data, :payload, %{})
    model = Map.get(payload, :model_name) || Map.get(payload, :model)
    guess_provider_from_model(model)
  end

  defp guess_provider_from_model(nil), do: "unknown"
  defp guess_provider_from_model(model) when is_binary(model) do
    cond do
      String.contains?(model, "gemini") -> "google"
      String.contains?(model, "claude") -> "anthropic"
      String.contains?(model, "gpt") -> "openai"
      true -> "unknown"
    end
  end

  defp has_tool_calls?(payload) when is_map(payload) do
    case Map.get(payload, :tool_calls) do
      calls when is_list(calls) -> length(calls) > 0
      _ -> false
    end
  end
  defp has_tool_calls?(_), do: false
end
```

### 2. Usage.Store (数据库操作)

```elixir
defmodule Cortex.Usage.Store do
  @moduledoc """
  Token 使用记录的数据库操作。
  """
  import Ecto.Query
  alias Cortex.Repo
  alias Cortex.Usage.Schema

  @doc "记录一次 token 使用"
  def record_usage(usage, metadata) do
    %Schema{}
    |> Schema.changeset(Map.merge(usage, metadata))
    |> Repo.insert()
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc "查询统计数据"
  def query_stats(opts \\\\ []) do
    base_query()
    |> apply_filters(opts)
    |> apply_grouping(opts)
    |> Repo.all()
  end

  @doc "按会话统计"
  def stats_by_session(session_id) do
    result = from(u in Schema,
      where: u.session_id == ^session_id,
      select: %{
        total_tokens: sum(u.total_tokens),
        prompt_tokens: sum(u.prompt_tokens),
        completion_tokens: sum(u.completion_tokens),
        request_count: count(u.id)
      }
    )
    |> Repo.one()

    # 修正：返回默认值避免 nil 崩溃
    result || %{
      total_tokens: 0,
      prompt_tokens: 0,
      completion_tokens: 0,
      request_count: 0
    }
  end

  @doc "按模型统计（最近 N 天）"
  def stats_by_model(days \\\\ 7) do
    # 修正：强制 days 上限为 90
    days = min(days, 90)
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 86400, :second)

    from(u in Schema,
      where: u.inserted_at >= ^cutoff,
      group_by: u.model,
      select: %{
        model: u.model,
        total_tokens: sum(u.total_tokens),
        request_count: count(u.id)
      },
      order_by: [desc: sum(u.total_tokens)]
    )
    |> Repo.all()
  end

  @doc "按日期统计（最近 N 天）"
  def stats_by_date(days \\\\ 30) do
    # 修正：强制 days 上限为 90
    days = min(days, 90)
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 86400, :second)

    from(u in Schema,
      where: u.inserted_at >= ^cutoff,
      group_by: fragment("DATE(?)", u.inserted_at),
      select: %{
        date: fragment("DATE(?)", u.inserted_at),
        total_tokens: sum(u.total_tokens),
        request_count: count(u.id)
      },
      order_by: [asc: fragment("DATE(?)", u.inserted_at)]
    )
    |> Repo.all()
  end

  @doc "重置所有统计数据（危险操作）"
  def reset_all do
    Repo.delete_all(Schema)
  end

  @doc "删除指定会话的统计数据"
  def delete_by_session(session_id) do
    from(u in Schema, where: u.session_id == ^session_id)
    |> Repo.delete_all()
  end

  # 私有辅助函数
  defp base_query, do: from(u in Schema)

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:session_id, sid}, q -> where(q, [u], u.session_id == ^sid)
      {:model, model}, q -> where(q, [u], u.model == ^model)
      {:channel, ch}, q -> where(q, [u], u.channel == ^ch)
      {:since, dt}, q -> where(q, [u], u.inserted_at >= ^dt)
      _, q -> q
    end)
  end

  defp apply_grouping(query, opts) do
    case Keyword.get(opts, :group_by) do
      :model -> group_by(query, [u], u.model)
      :date -> group_by(query, [u], fragment("DATE(?)", u.inserted_at))
      _ -> query
    end
  end
end
```

### 3. LLM 工具：GetTokenUsage

```elixir
defmodule Cortex.Tools.Handlers.GetTokenUsage do
  @behaviour Cortex.Tools.ToolBehaviour

  alias Cortex.Usage.Store

  @impl true
  def execute(args, ctx) do
    scope = Map.get(args, :scope, "session")
    days = Map.get(args, :days, 7)
    # 修正：强制 days 上限为 90
    days = min(days, 90)

    result =
      case scope do
        "session" ->
          session_id = Map.get(ctx, :session_id)
          Store.stats_by_session(session_id)

        "model" ->
          Store.stats_by_model(days)

        "date" ->
          Store.stats_by_date(days)

        "all" ->
          %{
            by_model: Store.stats_by_model(days),
            by_date: Store.stats_by_date(days)
          }

        _ ->
          {:error, "Unknown scope: #{scope}"}
      end

    case result do
      {:error, _} = err -> err
      data -> {:ok, Jason.encode!(data, pretty: true)}
    end
  end
end
```

### 4. LLM 工具：ResetTokenUsage

```elixir
defmodule Cortex.Tools.Handlers.ResetTokenUsage do
  @behaviour Cortex.Tools.ToolBehaviour

  alias Cortex.Usage.Store
  alias Cortex.SignalHub

  @impl true
  def execute(args, ctx) do
    scope = Map.get(args, :scope, "session")

    result =
      case scope do
        "session" ->
          session_id = Map.get(ctx, :session_id)
          Store.delete_by_session(session_id)

        "all" ->
          Store.reset_all()

        _ ->
          {:error, "Unknown scope: #{scope}"}
      end

    case result do
      {count, _} when is_integer(count) ->
        SignalHub.emit("usage.reset", %{
          provider: "usage",
          event: "reset",
          action: "completed",
          actor: "llm_agent",
          origin: %{
            channel: "tool",
            client: "reset_token_usage",
            platform: "server",
            session_id: Map.get(ctx, :session_id)
          },
          scope: scope,
          deleted_count: count
        }, source: "/tool/usage")

        {:ok, "Deleted #{count} usage records (scope: #{scope})"}

      {:error, reason} ->
        {:error, "Reset failed: #{inspect(reason)}"}
    end
  end
end
```

---

## ConfigExtension 工具注册

在 `lib/cortex/extensions/config_extension.ex` 的 `tools/0` 函数中添加：

```elixir
%Cortex.Tools.Tool{
  name: "get_token_usage",
  description: "Query token usage statistics (by session, model, or date range).",
  parameters: [
    scope: [type: :string, required: false, doc: "Scope: session | model | date | all (default: session)"],
    days: [type: :integer, required: false, doc: "Number of days to query (default: 7, max: 90)"]
  ],
  module: Cortex.Tools.Handlers.GetTokenUsage
},
%Cortex.Tools.Tool{
  name: "reset_token_usage",
  description: "Reset token usage statistics (requires approval).",
  parameters: [
    scope: [type: :string, required: false, doc: "Scope: session | all (default: session)"]
  ],
  module: Cortex.Tools.Handlers.ResetTokenUsage
}
```

---

## UI 组件

### UsageComponent (LiveView)

位置：`lib/cortex_web/live/settings_live/usage_component.ex`

**功能：**
- 展示最近 7/30 天的 token 消耗趋势图（纯 SVG 折线图）
- 按模型分组的柱状图（纯 SVG）
- 当前会话的实时统计
- 支持导出 CSV

**技术栈：**
- Phoenix LiveView
- **纯 SVG 渲染**（无需 Chart.js，避免增加依赖）
- Tailwind CSS

**修正说明：**
- 原计划使用 Chart.js，但项目未引入该库
- 改用 LiveView 内嵌 SVG 绘制图表，参考 Phoenix LiveView 的 `Phoenix.LiveView.JS` 和 Tailwind CSS
- 图表渲染逻辑在服务端完成，客户端只负责展示 SVG
- **`@max_tokens` 和 `@max_daily_tokens` 计算**：
  ```elixir
  # 在 LiveView 的 mount/3 或 handle_info/2 中计算
  max_tokens = 
    @model_stats
    |> Enum.map(& &1.total_tokens)
    |> Enum.max(fn -> 1 end)  # 默认值 1，避免除零
  
  max_daily_tokens = 
    @date_stats
    |> Enum.map(& &1.total_tokens)
    |> Enum.max(fn -> 1 end)  # 默认值 1，避免除零
  ```

**示例布局：**

```heex
<div class="flex-1 flex flex-col overflow-hidden bg-slate-950">
  <div class="flex-1 overflow-y-auto p-6">
    <div class="mx-auto max-w-4xl">
      <h1 class="text-2xl font-bold mb-8 text-slate-100">Token Usage Statistics</h1>

      <!-- 当前会话统计 -->
      <div class="bg-slate-900 border border-slate-800 p-6 rounded-xl mb-6">
        <h2 class="text-base font-semibold text-slate-200 mb-4">Current Session</h2>
        <div class="grid grid-cols-3 gap-4">
          <div>
            <p class="text-sm text-slate-400">Total Tokens</p>
            <p class="text-2xl font-bold text-teal-400"><%= @session_stats.total_tokens %></p>
          </div>
          <div>
            <p class="text-sm text-slate-400">Requests</p>
            <p class="text-2xl font-bold text-slate-200"><%= @session_stats.request_count %></p>
          </div>
          <div>
            <p class="text-sm text-slate-400">Avg Tokens/Request</p>
            <p class="text-2xl font-bold text-slate-200"><%= avg_tokens(@session_stats) %></p>
          </div>
        </div>
      </div>

      <!-- 按模型统计 -->
      <div class="bg-slate-900 border border-slate-800 p-6 rounded-xl mb-6">
        <h2 class="text-base font-semibold text-slate-200 mb-4">Usage by Model (Last 7 Days)</h2>
        <!-- 纯 SVG 柱状图 -->
        <svg viewBox="0 0 600 300" class="w-full h-64">
          <%= for {stat, idx} <- Enum.with_index(@model_stats) do %>
            <% bar_height = stat.total_tokens / @max_tokens * 250 %>
            <% x = idx * 100 + 10 %>
            <rect 
              x={x} 
              y={300 - bar_height} 
              width="80" 
              height={bar_height}
              fill="#14b8a6"
              rx="4"
            />
            <text 
              x={x + 40} 
              y="290" 
              text-anchor="middle" 
              fill="#94a3b8" 
              font-size="12"
            >
              <%= String.slice(stat.model, 0..10) %>
            </text>
            <text 
              x={x + 40} 
              y={300 - bar_height - 5} 
              text-anchor="middle" 
              fill="#e2e8f0" 
              font-size="10"
            >
              <%= stat.total_tokens %>
            </text>
          <% end %>
        </svg>
      </div>

      <!-- 按日期统计 -->
      <div class="bg-slate-900 border border-slate-800 p-6 rounded-xl">
        <h2 class="text-base font-semibold text-slate-200 mb-4">Daily Usage Trend (Last 30 Days)</h2>
        <!-- 纯 SVG 折线图 -->
        <svg viewBox="0 0 600 300" class="w-full h-64">
          <%= if length(@date_stats) > 0 do %>
            <% points = Enum.with_index(@date_stats) 
                |> Enum.map(fn {stat, idx} -> 
                  x = idx * (600 / max(length(@date_stats) - 1, 1))
                  y = 300 - (stat.total_tokens / @max_daily_tokens * 250)
                  "#{x},#{y}"
                end)
                |> Enum.join(" ") %>
            <polyline 
              points={points} 
              fill="none" 
              stroke="#14b8a6" 
              stroke-width="2"
            />
            <%= for {stat, idx} <- Enum.with_index(@date_stats) do %>
              <% x = idx * (600 / max(length(@date_stats) - 1, 1)) %>
              <% y = 300 - (stat.total_tokens / @max_daily_tokens * 250) %>
              <circle cx={x} cy={y} r="4" fill="#14b8a6" />
            <% end %>
          <% end %>
        </svg>
      </div>
    </div>
  </div>
</div>
```

---

## 信号集成

| 信号类型 | 时机 | 数据字段 | 修正说明 |
|---|---|---|---|
| `agent.response` | LLM 响应完成 | `usage: %{prompt_tokens, completion_tokens, total_tokens}` | **需要在 AgentLoop 中补充 usage 字段** |
| ~~`usage.recorded`~~ | ~~记录成功~~ | ~~`session_id, model, total_tokens`~~ | **已删除**：避免级联信号，Collector 不发射此信号 |
| `usage.reset` | 重置统计 | `scope, deleted_count` | 保留，用于审计 |

**修正说明：**
- `usage.recorded` 信号已删除，避免触发级联反应
- `agent.response` 信号当前缺少 `usage` 字段，需要在 `AgentLoop` 中从 `ReqLLM.Response.usage/1` 提取并添加

---

## 实施任务（DAG）

```
T0: 在 AgentLoop 中提取 usage 并添加到 agent.response 信号（前置任务）
T1: 创建 Schema 和 Migration
T2: 实现 Usage.Store（数据库操作）
T3: 实现 Usage.Collector（信号监听）
T4: 在 Application.ex 中启动 Collector
T5: 实现 GetTokenUsage handler
T6: 实现 ResetTokenUsage handler
T7: 在 ConfigExtension 中注册工具
T8: 在 ToolInterceptor 中添加 reset_token_usage 审批规则
T9: 创建 UsageComponent LiveView（纯 SVG 渲染）
T10: 在 SettingsLive.Index 中添加 :usage action
T11: 在 Router 中添加 /settings/usage 路由
T12: 测试（mimic 信号发射 + 数据库查询）
```

**依赖关系：**
- T1 依赖 T0（必须先有 usage 字段）
- T2 依赖 T1
- T3 依赖 T2
- T4 依赖 T3
- T5, T6 依赖 T2
- T7 依赖 T5, T6
- T9 依赖 T2
- T10, T11 依赖 T9

**修正说明：**
- 新增 T0 任务：在 `AgentLoop` 中提取 `ReqLLM.Response.usage/1` 并添加到 `agent.response` 信号
- T9 改为纯 SVG 渲染，无需 Chart.js

---

## BDD 场景

```gherkin
Scenario: 记录 LLM 响应的 token 使用
  Given Agent 完成一次 LLM 调用，返回 usage: {prompt_tokens: 100, completion_tokens: 50}
  When 发射 agent.response 信号
  Then Usage.Collector 监听到信号
  And 插入一条记录到 token_usage_logs 表
  And 记录包含 session_id, model, total_tokens=150

Scenario: 查询当前会话的统计数据
  Given 当前会话已有 5 次 LLM 调用，总计 1000 tokens
  When Agent 调用 get_token_usage(scope: "session")
  Then 返回 {total_tokens: 1000, request_count: 5}

Scenario: 按模型统计最近 7 天
  Given 最近 7 天使用了 gemini-2.0-flash (5000 tokens) 和 claude-sonnet (3000 tokens)
  When Agent 调用 get_token_usage(scope: "model", days: 7)
  Then 返回按 total_tokens 降序排列的模型列表

Scenario: 重置会话统计（需审批）
  Given 当前会话有 10 条使用记录
  When Agent 调用 reset_token_usage(scope: "session")
  Then ToolInterceptor 拦截并请求用户批准
  And 用户批准后删除 10 条记录
  And 发射 usage.reset 信号

Scenario: UI 展示统计图表
  Given 用户访问 /settings/usage
  When LiveView 加载统计数据
  Then 展示当前会话的 total_tokens 和 request_count
  And 展示按模型分组的柱状图（纯 SVG）
  And 展示最近 30 天的折线图（纯 SVG）
```

---

## 安全与性能考虑

### 1. 数据隐私
- 不记录 prompt 和 response 内容，只记录 token 数量
- 支持按会话删除，用户可清除自己的统计数据

### 2. 性能优化
- Collector 使用异步 GenServer，不阻塞 Agent 主流程
- 数据库索引：`session_id`, `model`, `inserted_at`
- 聚合查询使用 Ecto 的 `group_by` 和 `sum`，避免内存加载全量数据

### 3. 审批机制
- `reset_token_usage` 工具需要通过 ToolInterceptor 审批
- `get_token_usage` 为只读操作，无需审批

### 4. 降级策略
- 如果 Collector 启动失败，不影响 Agent 正常运行
- 如果数据库写入失败，只记录 warning 日志，不抛出异常

---

## 本期不包含

- 成本估算（需要各模型的定价数据）
- 实时流式统计（当前为批量记录）
- 跨会话的用户级统计（需要用户认证系统）
- Webhook 通知（token 超限告警）

---

## 参考资料

- **Gong TokenEstimator**: `docs/gong-master/lib/gong/compaction/token_estimator.ex`
- **Arbor TokenBudget**: `docs/arbor_reference/lib/arbor/memory/token_budget.ex`
- **ReqLLM Usage**: `ReqLLM.Response.usage/1` 返回 `%{prompt_tokens, completion_tokens, total_tokens}`
- **搜索能力规划**: `docs/plans/20260225_agent_search_capability_planning.md`

---

## 附录：ReqLLM.Response.usage 数据结构

根据 ReqLLM 文档，`usage/1` 返回的数据结构为：

```elixir
%{
  prompt_tokens: 150,        # 输入 tokens
  completion_tokens: 80,     # 输出 tokens
  total_tokens: 230          # 总计 tokens
}
```

部分提供商（如 Anthropic）可能还包含：
- `cache_creation_input_tokens`: 缓存创建的输入 tokens
- `cache_read_input_tokens`: 从缓存读取的输入 tokens

当前实现只记录标准的三个字段，未来可扩展支持缓存相关字段。
