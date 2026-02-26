# Agent 搜索能力规划 V2

**日期**: 2026-02-25  
**版本**: V2（基于 V1 评审修订）  
**参考**: nanobot PR#547 (降级链), OpenClaw Tavily 插件 (Extension 化)

---

## V1 评审问题总结

| # | 问题 | 严重度 | V2 修正 |
|---|---|---|---|
| 1 | `SearchExtension` 混用 Extension behaviour 和 GenServer，与实际 `Loader` 机制不符 | 高 | Extension 保持无状态，信号监听由独立 GenServer `SearchConfigWatcher` 负责 |
| 2 | 配置读取优先级 "DB > runtime.exs > 环境变量" 过于复杂 | 中 | 简化为 "DB（如有）→ runtime.exs 环境变量"，与现有 `Config.Settings` 的 `persistent_term` 模式对齐 |
| 3 | 与 LLM 可配置设置计划大量重叠（SearchSettings schema、update_search_config handler） | 高 | 本计划只负责搜索核心能力（Provider + Dispatcher + Extension），配置工具和 UI 由 LLM 可配置设置计划统一负责 |
| 4 | `ToolRunner` 无审批拦截机制，计划中的审批流程无法落地 | 高 | 搜索工具本身不需要审批（只读操作），移除审批相关设计 |
| 5 | DAG 中 UI 任务（T9-T11）与搜索核心能力耦合 | 中 | UI 和配置工具任务移至 LLM 可配置设置计划 |
| 6 | 缺少 HTTP 客户端错误处理和超时策略 | 中 | 新增 Provider 级别的超时和重试规范 |

---

## 核心决策

- Brave 和 Tavily **同等地位**，用户通过 DB 配置或环境变量指定默认
- 搜索以 **Extension 插件**形式集成，通过 `Loader` → `register_dynamic` 注册工具
- 降级链：`configured_default → first available → error`
- **职责边界**：本计划只覆盖搜索引擎核心能力，配置 UI 和 LLM 配置工具由 [LLM 可配置设置计划](./20260225_llm_configurable_settings_planning_v2.md) 负责

---

## 架构分层

```
Agent (tool call: web_search)
    │
    ▼
Cortex.Tools.Handlers.WebSearch          ← ToolBehaviour 入口（由 Extension 注册）
    │
    ▼
Cortex.Search.Dispatcher                 ← 路由 & 降级
    │
    ├── Cortex.Search.Providers.Brave    ← Brave Web Search API (Req)
    └── Cortex.Search.Providers.Tavily   ← Tavily Search API (Req)
```

---

## 文件结构

```
lib/cortex/
├── search/
│   ├── provider.ex                      # Provider behaviour
│   ├── dispatcher.ex                    # 路由 & 降级逻辑
│   └── providers/
│       ├── brave.ex                     # Brave 实现 (Req)
│       └── tavily.ex                    # Tavily 实现 (Req)
├── tools/handlers/
│   └── web_search.ex                    # ToolBehaviour 入口
└── extensions/
    └── search_extension.ex              # Extension behaviour（无状态，仅注册工具）
```

**注意**：以下文件由 LLM 可配置设置计划负责，不在本计划范围内：
- `lib/cortex/config/search_settings.ex`（DB schema）
- `lib/cortex/tools/handlers/update_search_config.ex`（配置工具）
- `lib/cortex_web/live/settings_live/search_component.ex`（UI）

---

## Provider Behaviour

```elixir
defmodule Cortex.Search.Provider do
  @type result :: %{
    title: String.t(),
    url: String.t(),
    snippet: String.t(),
    published_date: String.t() | nil
  }

  @callback search(query :: String.t(), opts :: keyword()) ::
              {:ok, [result()]} | {:error, term()}
  @callback name() :: String.t()
  @callback available?() :: boolean()
end
```

---

## Dispatcher 降级逻辑

```elixir
defmodule Cortex.Search.Dispatcher do
  @providers [
    brave: Cortex.Search.Providers.Brave,
    tavily: Cortex.Search.Providers.Tavily
  ]

  def search(query, opts \\ []) do
    provider_mod = resolve_provider(opts[:provider])

    case provider_mod do
      nil -> {:error, "No search provider configured. Set BRAVE_API_KEY or TAVILY_API_KEY."}
      mod -> mod.search(query, opts)
    end
  end

  # 1. 强制指定 provider → 直接使用（不降级）
  # 2. 读取 DB/config 中的 default_provider
  # 3. 若 default provider available? → 使用它
  # 4. 否则遍历 @providers，取第一个 available? 的
  # 5. 全部不可用 → nil
  defp resolve_provider(forced) when is_binary(forced) do
    key = String.to_existing_atom(forced)
    mod = @providers[key]
    if mod && mod.available?(), do: mod, else: nil
  end

  defp resolve_provider(_) do
    default = get_default_provider()

    cond do
      default && @providers[default] && @providers[default].available?() ->
        @providers[default]

      true ->
        Enum.find_value(@providers, fn {_key, mod} ->
          if mod.available?(), do: mod
        end)
    end
  end

  defp get_default_provider do
    # 优先从 DB 读取（如果 SearchSettings 存在），否则从 Application config
    case search_settings_from_db() do
      %{default_provider: p} when is_binary(p) and p != "" ->
        String.to_existing_atom(p)
      _ ->
        Application.get_env(:cortex, :search, [])[:default_provider] || :tavily
    end
  end

  defp search_settings_from_db do
    # 安全调用，如果 SearchSettings 模块不存在或表不存在则返回 nil
    try do
      Cortex.Config.SearchSettings.get_settings()
    rescue
      _ -> nil
    end
  end
end
```

---

## Provider 实现示例（Tavily）

```elixir
defmodule Cortex.Search.Providers.Tavily do
  @behaviour Cortex.Search.Provider

  @impl true
  def name, do: "tavily"

  @impl true
  def available? do
    api_key() != nil and api_key() != ""
  end

  @impl true
  def search(query, opts \\ []) do
    count = Keyword.get(opts, :count, 5) |> min(10)

    case Req.post(base_url() <> "/search",
           json: %{query: query, max_results: count, api_key: api_key()},
           receive_timeout: 15_000
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        results = parse_results(body)
        {:ok, results}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "Tavily API error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Tavily request failed: #{inspect(reason)}"}
    end
  end

  defp parse_results(%{"results" => results}) when is_list(results) do
    Enum.map(results, fn r ->
      %{
        title: r["title"] || "",
        url: r["url"] || "",
        snippet: r["content"] || "",
        published_date: r["published_date"]
      }
    end)
  end

  defp parse_results(_), do: []

  defp api_key do
    # DB 优先，fallback 到环境变量
    case search_settings_field(:tavily_api_key) do
      key when is_binary(key) and key != "" -> key
      _ -> System.get_env("TAVILY_API_KEY")
    end
  end

  defp base_url do
    Application.get_env(:cortex, :search, [])
    |> get_in([:providers, :tavily, :base_url]) || "https://api.tavily.com"
  end

  defp search_settings_field(field) do
    try do
      settings = Cortex.Config.SearchSettings.get_settings()
      Map.get(settings, field)
    rescue
      _ -> nil
    end
  end
end
```

---

## Extension 注册（无状态）

```elixir
defmodule Cortex.Extensions.SearchExtension do
  @behaviour Cortex.Extensions.Extension

  def name, do: "search"
  def description, do: "Web search capability via Brave or Tavily"
  def hooks, do: []

  def tools do
    [
      %Cortex.Tools.Tool{
        name: "web_search",
        description: "Search the web for real-time information. Returns titles, URLs, and snippets.",
        parameters: [
          query:    [type: :string,  required: true,  doc: "The search query"],
          count:    [type: :integer, required: false, doc: "Number of results (default: 5, max: 10)"],
          provider: [type: :string,  required: false, doc: "Force a specific provider: brave | tavily"]
        ],
        module: Cortex.Tools.Handlers.WebSearch
      }
    ]
  end

  def init(_config) do
    # 无状态，Loader 会自动调用 register_dynamic 注册工具
    {:ok, %{}}
  end
end
```

**关键区别**：V1 中 `SearchExtension` 混用了 `GenServer` 和 `Extension behaviour`。V2 严格遵循现有 `Loader` 机制 — Extension 是无状态的，`init/1` 只返回 `{:ok, state}`，工具注册由 `Loader.load_extension/1` 自动完成。

---

## WebSearch Handler

```elixir
defmodule Cortex.Tools.Handlers.WebSearch do
  @behaviour Cortex.Tools.ToolBehaviour

  alias Cortex.Search.Dispatcher

  @impl true
  def execute(args, _ctx) do
    query = Map.get(args, :query) || Map.get(args, "query", "")
    count = Map.get(args, :count) || Map.get(args, "count", 5)
    provider = Map.get(args, :provider) || Map.get(args, "provider")

    opts = [count: count]
    opts = if provider, do: Keyword.put(opts, :provider, provider), else: opts

    case Dispatcher.search(query, opts) do
      {:ok, results} ->
        formatted = format_results(results)
        {:ok, formatted}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_results(results) do
    results
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {r, i} ->
      "#{i}. #{r.title}\n   URL: #{r.url}\n   #{r.snippet}"
    end)
  end
end
```

---

## 配置（config/runtime.exs）

```elixir
config :cortex, :search,
  default_provider: :tavily,
  providers: [
    brave: [
      api_key: System.get_env("BRAVE_API_KEY"),
      base_url: "https://api.search.brave.com/res/v1"
    ],
    tavily: [
      api_key: System.get_env("TAVILY_API_KEY"),
      base_url: "https://api.tavily.com"
    ]
  ]
```

---

## 信号集成

| 信号类型 | 时机 | 说明 |
|---|---|---|
| `tool.call.web_search` | 发起搜索前 | 由 `LlmAgent.ToolExecution` 自动发射 |
| `tool.result.web_search` | 搜索成功 | 由 `Broadcaster` 自动发射 |
| `tool.error.web_search` | 搜索失败 | 由 `Broadcaster` 自动发射 |

**注意**：这些信号由现有的 `LlmAgent` tool execution 流程自动处理，无需在 `SignalCatalog` 中额外注册。

---

## 实施任务（DAG）

```
T1: Provider behaviour (search/provider.ex)
T2: Brave provider 实现 (search/providers/brave.ex)        ← 依赖 T1
T3: Tavily provider 实现 (search/providers/tavily.ex)      ← 依赖 T1
T4: Dispatcher 路由 + 降级链 (search/dispatcher.ex)        ← 依赖 T1
T5: WebSearch handler (tools/handlers/web_search.ex)       ← 依赖 T4
T6: SearchExtension (extensions/search_extension.ex)       ← 依赖 T5
T7: config/runtime.exs 添加 :search 配置项
T8: application.ex 中加载 SearchExtension                  ← 依赖 T6
T9: 测试（mimic HTTP，覆盖降级场景）                         ← 依赖 T2-T6

依赖图：
T1 → T2, T3, T4
T4 → T5 → T6 → T8
T7 (独立)
T2, T3, T4, T5, T6 → T9
```

**已移至 LLM 可配置设置计划的任务**：
- SearchSettings schema + migration
- SearchComponent LiveView（UI 配置页面）
- Router 添加 /settings/search 路由
- update_search_config handler

---

## BDD 场景

```gherkin
Feature: Agent 搜索能力

  Scenario: Tavily 为默认，成功搜索
    Given TAVILY_API_KEY 已配置，default_provider: :tavily
    When Agent 调用 web_search(query: "elixir genserver")
    Then 返回最多 5 条结果（title, url, snippet）
    And 结果通过 tool.result.web_search 信号广播

  Scenario: 默认 provider 不可用，自动降级
    Given TAVILY_API_KEY 未设置，BRAVE_API_KEY 已配置
    When Agent 调用 web_search(query: "anything")
    Then Dispatcher 自动降级到 Brave 并返回结果

  Scenario: 所有 provider 均未配置
    Given 无任何 API key
    When Agent 调用 web_search(query: "test")
    Then 返回错误 "No search provider configured"

  Scenario: 强制指定 provider
    When Agent 调用 web_search(query: "test", provider: "brave")
    Then 忽略 default_provider，直接使用 Brave
    And 若 Brave 不可用，返回错误（不降级）

  Scenario: Provider API 超时
    Given Tavily API 响应超过 15 秒
    When Agent 调用 web_search(query: "slow query")
    Then 返回超时错误，不阻塞 Agent 主循环

  Scenario: 新增 provider 扩展
    Given 新增 Serper 实现了 Provider behaviour
    When 在 @providers 列表中注册 serper
    Then Dispatcher 自动识别，无需修改其他代码
```

---

## BDD 驱动迭代流程说明

本计划遵循 BDD 驱动的任务迭代流程（参考 `.agent/skills/bddc/SKILL.md`）：

1. **规划阶段**（当前）：完成架构分析、任务 DAG 和 BDD 场景定义
2. **BDD 编译**：将上述 Gherkin 场景通过 `bddc` 编译为 ExUnit 测试骨架
3. **红灯实现**：运行测试确认全部失败（红灯）
4. **绿灯实现**：按 DAG 顺序逐任务实现，每完成一个任务运行测试
5. **重构**：所有测试通过后进行代码清理

---

## 本期不包含

- 搜索结果缓存
- `tavily_extract` / `tavily_crawl` 等扩展工具
- DuckDuckGo / Serper 等其他 provider
- UI 配置页面（由 LLM 可配置设置计划负责）
- LLM 配置工具（由 LLM 可配置设置计划负责）
