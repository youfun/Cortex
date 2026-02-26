# Agent 搜索能力规划

**日期**: 2026-02-25  
**参考**: nanobot PR#547 (降级链), OpenClaw Tavily 插件 (Extension 化)

---

## 核心决策

- Brave 免费层已停止，**Brave 和 Tavily 同等地位**，用户通过 config 指定默认
- 搜索以 **Extension 插件**形式集成，通过 `register_dynamic` 注册工具，不污染内置 Registry
- 降级链参考 nanobot：`configured_default → first available → error`

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
    ├── Cortex.Search.Providers.Brave    ← Brave Web Search API
    └── Cortex.Search.Providers.Tavily   ← Tavily Search API
```

## 文件结构

```
lib/cortex/
├── search/
│   ├── provider.ex                      # Provider behaviour
│   ├── dispatcher.ex                    # 路由 & 降级逻辑
│   └── providers/
│       ├── brave.ex                     # Brave 实现
│       └── tavily.ex                    # Tavily 实现
├── tools/handlers/
│   └── web_search.ex                    # ToolBehaviour 入口
└── extensions/
    └── search_extension.ex              # Extension，启动时注册 web_search 工具
```

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
  @callback available?() :: boolean()  # 检查 API key 是否已配置
end
```

## Dispatcher 降级逻辑

```elixir
# 1. 读取 config 中的 default_provider
# 2. 若 default provider available? → 使用它
# 3. 否则遍历所有 providers，取第一个 available? 的
# 4. 全部不可用 → {:error, "No search provider configured. Set BRAVE_API_KEY or TAVILY_API_KEY."}
```

## Extension 注册

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
        description: "Search the web for real-time information.",
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
    Enum.each(tools(), &Cortex.Tools.Registry.register_dynamic/1)
    {:ok, %{}}
  end
end
```

---

## 配置（config/runtime.exs）

```elixir
config :cortex, :search,
  default_provider: :tavily,   # 或 :brave，用户自行设置
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

Extension 在 `application.ex` 中通过 `Extensions.Manager` 加载，与现有 Extension 机制一致。

---

## 信号集成

| 信号类型 | 时机 |
|---|---|
| `tool.call.web_search` | 发起搜索前 |
| `tool.result.web_search` | 搜索成功 |
| `tool.error.web_search` | 搜索失败或无可用 provider |

---

## 实施任务（DAG）

```
T1: Provider behaviour (provider.ex)
T2: Brave provider 实现
T3: Tavily provider 实现
T4: Dispatcher（路由 + 降级链）
T5: WebSearch handler（ToolBehaviour）
T6: SearchExtension（Extension behaviour + 工具注册）
T7: config/runtime.exs 添加 :search 配置项
T8: SignalCatalog 添加 web_search 信号类型
T9: SearchSettings schema + migration（DB 配置存储）
T10: SearchComponent LiveView（UI 配置页面）
T11: Router 添加 /settings/search 路由
T12: 测试（mimic HTTP，覆盖降级场景 + UI 交互）
```

---

## BDD 场景

```gherkin
Scenario: Tavily 为默认，成功搜索
  Given TAVILY_API_KEY 已配置，default_provider: :tavily
  When Agent 调用 web_search(query: "elixir genserver")
  Then 返回最多 5 条结果（title, url, snippet）
  And 发射 tool.result.web_search 信号

Scenario: 默认 provider 不可用，自动降级
  Given TAVILY_API_KEY 未设置，BRAVE_API_KEY 已配置
  When Agent 调用 web_search(query: "anything")
  Then Dispatcher 自动降级到 Brave 并返回结果

Scenario: 所有 provider 均未配置
  Given 无任何 API key
  When Agent 调用 web_search
  Then 返回错误 "No search provider configured"

Scenario: 强制指定 provider
  When Agent 调用 web_search(query: "test", provider: "brave")
  Then 忽略 default_provider，直接使用 Brave

Scenario: 新增 provider 扩展
  Given 新增 Serper 实现了 Provider behaviour
  When 在 config providers 中注册 serper
  Then Dispatcher 自动识别，无需修改其他代码
```

---

---

## UI 配置页面

在 `/settings/search` 添加第三个 tab，与 Channels、Models 并列。

**注**：配置页面的所有设置项都可以通过 LLM tool call 修改，详见 [LLM 可配置设置系统规划](./20260225_llm_configurable_settings_planning.md)。

### 配置项

| 字段 | 类型 | 说明 |
|---|---|---|
| `default_provider` | select | brave / tavily |
| `brave_api_key` | password | Brave API Key（可选） |
| `tavily_api_key` | password | Tavily API Key（可选） |
| `enable_llm_title_generation` | checkbox | 是否使用 LLM 生成表头（预留） |

### 实现要点

- 配置存储在 `Cortex.Config.SearchSettings` schema（新建 Ecto schema）
- 读取优先级：DB > runtime.exs > 环境变量
- 保存后发射 `config.search.updated` 信号，Extension 监听并重新加载 provider
- 支持通过 `update_search_config` 工具在 SNS 通道（Telegram/Feishu）上远程配置

### 文件变更

```
lib/cortex/config/
  └── search_settings.ex              # Ecto schema

lib/cortex_web/live/settings_live/
  ├── index.ex                        # 添加 :search action
  └── search_component.ex             # 新建 LiveComponent

lib/cortex/tools/handlers/
  └── update_search_config.ex         # LLM 配置工具

priv/repo/migrations/
  └── YYYYMMDDHHMMSS_create_search_settings.exs
```

---

## 本期不包含

- 搜索结果缓存
- `tavily_extract` / `tavily_crawl` 等扩展工具
- DuckDuckGo / Serper 等其他 provider
