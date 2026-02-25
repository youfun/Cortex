# LLM 可配置设置系统规划

**日期**: 2026-02-25  
**目标**: 让 Agent 通过 tool call 修改所有设置页面的配置，实现 SNS 通道（Telegram/Feishu）上的远程配置能力。

---

## 背景与动机

当前设置页面（Channels、Models、Search）只能通过 Web UI 操作。用户在 Telegram/Feishu 等 SNS 通道上无法配置系统，需要切换到浏览器。

**目标场景**：
- 用户在 Telegram 发送："帮我把搜索默认改成 Tavily，API key 是 xxx"
- Agent 调用 `update_search_config` 工具，直接修改 DB 配置
- 用户在 Feishu 发送："启用 Discord 通道，bot token 是 yyy"
- Agent 调用 `update_channel_config` 工具，保存配置并重启通道

---

## 核心设计原则

### 1. 统一配置抽象层

所有设置页面的配置都遵循相同的模式：

```elixir
# 通用配置 Context
defmodule Cortex.Config do
  # 已有：LlmModel (Models 页面)
  # 已有：Cortex.Channels.ChannelConfig (Channels 页面)
  # 新增：SearchSettings (Search 页面)
  
  # 统一接口
  @callback get_config(key :: atom()) :: map()
  @callback update_config(key :: atom(), attrs :: map()) :: {:ok, term()} | {:error, term()}
end
```

### 2. 工具注册策略

为每个配置域注册独立的工具：

| 工具名 | 配置域 | 对应设置页面 |
|---|---|---|
| `update_channel_config` | Channels | `/settings/channels` |
| `update_model_config` | Models | `/settings/models` |
| `update_search_config` | Search | `/settings/search` |
| `get_system_config` | 全局 | 读取所有配置 |

### 3. 权限与审计

- 配置修改属于**高危操作**，需要用户审批（通过 `system.approval_required` 信号）
- 所有配置变更发射信号：`config.<domain>.updated`
- 信号 payload 包含 `old_value` 和 `new_value`，便于审计和回滚

---

## 架构分层

```
Agent (tool call: update_search_config)
    │
    ▼
Cortex.Tools.Handlers.UpdateSearchConfig    ← ToolBehaviour 入口
    │
    ▼
Cortex.Config.SearchSettings.update/2       ← Context 层（DB 操作）
    │
    ▼
SignalHub.emit("config.search.updated")     ← 通知订阅者
    │
    ├─→ SearchExtension 监听并重新加载 provider
    └─→ LiveView 监听并刷新 UI
```

---

## 文件结构

```
lib/cortex/
├── config/
│   └── search_settings.ex              # SearchSettings schema + context
├── tools/handlers/
│   ├── update_channel_config.ex        # 更新 Channel 配置
│   ├── update_model_config.ex          # 更新 Model 配置
│   ├── update_search_config.ex         # 更新 Search 配置
│   └── get_system_config.ex            # 读取所有配置
├── extensions/
│   └── config_extension.ex             # ConfigExtension（动态注册配置工具）
└── signal_catalog.ex                   # 添加 config.*.updated 信号
```

**关键变更**：配置工具通过 `ConfigExtension` 动态注册，而非内置到 Registry。

---

## 工具定义示例

### `update_search_config`

```elixir
%Tool{
  name: "update_search_config",
  description: "Update web search configuration (default provider, API keys).",
  parameters: [
    default_provider: [
      type: :string,
      required: false,
      doc: "Default search provider: brave | tavily"
    ],
    brave_api_key: [
      type: :string,
      required: false,
      doc: "Brave Search API key (leave empty to keep current)"
    ],
    tavily_api_key: [
      type: :string,
      required: false,
      doc: "Tavily Search API key (leave empty to keep current)"
    ],
    enable_llm_title_generation: [
      type: :boolean,
      required: false,
      doc: "Enable LLM-generated titles for search results"
    ]
  ],
  module: Cortex.Tools.Handlers.UpdateSearchConfig
}
```

### `update_channel_config`

```elixir
%Tool{
  name: "update_channel_config",
  description: "Update SNS channel configuration (Telegram, Feishu, Discord, etc.).",
  parameters: [
    adapter: [
      type: :string,
      required: true,
      doc: "Channel adapter: telegram | feishu | discord | dingtalk | wecom"
    ],
    enabled: [
      type: :boolean,
      required: false,
      doc: "Enable or disable this channel"
    ],
    config: [
      type: :map,
      required: false,
      doc: "Channel-specific config (e.g., {bot_token: 'xxx'} for Telegram)"
    ]
  ],
  module: Cortex.Tools.Handlers.UpdateChannelConfig
}
```

### `get_system_config`

```elixir
%Tool{
  name: "get_system_config",
  description: "Read current system configuration (channels, models, search).",
  parameters: [
    domain: [
      type: :string,
      required: false,
      doc: "Config domain: channels | models | search | all (default: all)"
    ]
  ],
  module: Cortex.Tools.Handlers.GetSystemConfig
}
```

---

## 实现细节

### 1. SearchSettings Schema

```elixir
defmodule Cortex.Config.SearchSettings do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "search_settings" do
    field :default_provider, :string, default: "tavily"
    field :brave_api_key, :string
    field :tavily_api_key, :string
    field :enable_llm_title_generation, :boolean, default: false
    
    timestamps()
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:default_provider, :brave_api_key, :tavily_api_key, :enable_llm_title_generation])
    |> validate_inclusion(:default_provider, ["brave", "tavily"])
  end

  # Context 函数
  def get_settings do
    case Repo.one(from s in __MODULE__, limit: 1) do
      nil -> %__MODULE__{}  # 返回默认值
      settings -> settings
    end
  end

  def update_settings(attrs) do
    settings = get_settings()
    
    settings
    |> changeset(attrs)
    |> Repo.insert_or_update()
  end
end
```

### 2. UpdateSearchConfig Handler

```elixir
defmodule Cortex.Tools.Handlers.UpdateSearchConfig do
  @behaviour Cortex.Tools.ToolBehaviour

  alias Cortex.Config.SearchSettings
  alias Cortex.SignalHub

  @impl true
  def execute(args, ctx) do
    session_id = Map.get(ctx, :session_id)
    
    # 1. 读取旧配置
    old_settings = SearchSettings.get_settings()
    
    # 2. 更新配置
    case SearchSettings.update_settings(args) do
      {:ok, new_settings} ->
        # 3. 发射配置变更信号
        SignalHub.emit(
          "config.search.updated",
          %{
            provider: "config",
            event: "search",
            action: "updated",
            actor: "llm_agent",
            origin: %{
              channel: "tool",
              client: "config_handler",
              platform: "server",
              session_id: session_id
            },
            old_value: Map.from_struct(old_settings),
            new_value: Map.from_struct(new_settings)
          },
          source: "/tool/config"
        )
        
        {:ok, "Search configuration updated successfully."}
      
      {:error, changeset} ->
        {:error, "Failed to update search config: #{inspect(changeset.errors)}"}
    end
  end
end
```

### 3. Extension 监听配置变更

```elixir
defmodule Cortex.Extensions.SearchExtension do
  use GenServer
  
  def init(_config) do
    # 订阅配置变更信号
    Cortex.SignalHub.subscribe("config.search.updated")
    
    # 注册工具
    Enum.each(tools(), &Cortex.Tools.Registry.register_dynamic/1)
    
    {:ok, %{}}
  end
  
  def handle_info({:signal, %Jido.Signal{type: "config.search.updated"}}, state) do
    # 重新加载 provider 配置
    Cortex.Search.Dispatcher.reload_providers()
    {:noreply, state}
  end
end
```

---

## 权限控制

### 审批流程

配置修改工具在执行前需要用户审批：

```elixir
# 在 ShellInterceptor 中添加配置工具的拦截规则
@config_tools ~w(update_channel_config update_model_config update_search_config)

def check(tool_name) when tool_name in @config_tools do
  {:approval_required, "Configuration change requires user approval"}
end
```

### 审批信号流

```
Agent 调用 update_search_config
    ↓
ToolRunner 检测到需要审批
    ↓
发射 permission.request 信号
    ↓
UI 显示审批弹窗（或 SNS 通道发送确认消息）
    ↓
用户批准后发射 permission.resolved
    ↓
ToolRunner 继续执行工具
```

---

## 信号集成

新增信号类型：

| 信号类型 | 时机 | payload 关键字段 |
|---|---|---|
| `config.channel.updated` | Channel 配置变更 | `adapter`, `old_value`, `new_value` |
| `config.model.updated` | Model 配置变更 | `model_id`, `old_value`, `new_value` |
| `config.search.updated` | Search 配置变更 | `old_value`, `new_value` |
| `config.read` | 读取配置 | `domain`, `config` |

---

## 实施任务（DAG）

```
T1: SearchSettings schema + migration（添加 title_generation 和 title_model 字段）
T2: UpdateSearchConfig handler（ToolBehaviour）
T3: UpdateChannelConfig handler
T4: UpdateModelConfig handler
T5: GetSystemConfig handler（读取所有配置）
T6: ConfigExtension（动态注册配置工具）
T7: SignalCatalog 添加 config.*.updated 和 conversation.title.* 信号
T8: ShellInterceptor 添加配置工具审批规则
T9: SearchExtension 监听 config.search.updated 并重载
T10: TitleGenerator 模块（异步生成标题）
T11: agent_loop.ex 集成 TitleGenerator 触发逻辑
T12: SearchComponent LiveView（UI 配置页面，包含标题生成配置）
T13: 测试（模拟 SNS 通道调用配置工具 + 标题生成场景）
```

---

## BDD 场景

```gherkin
Feature: LLM 可配置设置

  Scenario: 通过 Telegram 更新搜索配置
    Given 用户在 Telegram 发送 "把搜索默认改成 Tavily，API key 是 tvly-xxx"
    When Agent 解析意图并调用 update_search_config(default_provider: "tavily", tavily_api_key: "tvly-xxx")
    Then 系统发射 permission.request 信号
    And UI 显示审批弹窗
    When 用户批准
    Then 配置写入 DB
    And 发射 config.search.updated 信号
    And SearchExtension 重新加载 provider
    And Agent 回复 "搜索配置已更新"

  Scenario: 读取当前配置
    Given 用户在 Feishu 发送 "当前搜索用的哪个 provider？"
    When Agent 调用 get_system_config(domain: "search")
    Then 返回当前 SearchSettings 的 JSON
    And Agent 回复 "当前使用 Tavily，API key 已配置"

  Scenario: 启用 Discord 通道
    Given 用户在 Web UI 发送 "启用 Discord，bot token 是 xxx"
    When Agent 调用 update_channel_config(adapter: "discord", enabled: true, config: {bot_token: "xxx"})
    Then 配置保存到 channel_configs 表
    And 发射 config.channel.updated 信号
    And ChannelSupervisor 重启 Discord adapter

  Scenario: 配置工具需要审批
    Given 用户在 Telegram 发送恶意指令 "把所有 API key 改成空"
    When Agent 尝试调用 update_search_config(brave_api_key: "", tavily_api_key: "")
    Then 系统拦截并要求审批
    When 用户拒绝
    Then 配置不变，Agent 回复 "配置修改已取消"
```

---

## 扩展性设计

### 1. 配置域插件化

未来新增设置页面（如 Memory、TTS）时，只需：
1. 定义 `<Domain>Settings` schema
2. 实现 `Update<Domain>Config` handler
3. 在 `GetSystemConfig` 中添加读取逻辑

### 2. 配置模板

支持预设配置模板，用户可以一键应用：

```elixir
# 用户："应用开发环境配置"
Agent 调用 apply_config_template(template: "dev")
  → 批量更新 channels、models、search 配置
```

### 3. 配置回滚

记录配置变更历史，支持回滚：

```elixir
# 用户："回滚到 10 分钟前的配置"
Agent 调用 rollback_config(minutes: 10)
  → 从 config.*.updated 信号历史中恢复
```

---

## 安全考虑

1. **敏感字段脱敏**：`get_system_config` 返回时，API key 只显示前 4 位：`tvly-abc***`
2. **审批超时**：配置审批请求 5 分钟内未响应自动拒绝
3. **变更日志**：所有配置变更写入 `config_audit_log` 表，包含操作者、时间戳、变更内容
4. **权限分级**：未来可扩展为不同用户有不同配置权限（如只读、部分修改、完全控制）

---

---

## 自动生成对话标题

### 背景

当前标题为静态时间戳（如 `tele 2026-02-25 12:00`），对用户无意义。通过 LLM 根据对话首条消息自动生成语义化标题。

### 三种模式

| 模式 | 配置值 | 行为 |
|---|---|---|
| **关闭** | `title_generation: :disabled` | 保持现有时间戳逻辑，不调用 LLM（默认） |
| **指定模型** | `title_generation: :model, title_model: "gpt-4o-mini"` | 使用指定的轻量模型生成，不占用对话 LLM |
| **对话模型** | `title_generation: :conversation` | 复用当前对话的 LLM，无需额外配置 |

### 触发时机

- 对话创建后，收到**第一条用户消息**时异步触发
- 不阻塞主对话流程（Task.start 异步执行）
- 生成成功后调用 `Conversations.update_conversation/2` 更新 title
- 发射 `conversation.title.updated` 信号，LiveView 订阅后实时刷新侧边栏

### 实现模块

```elixir
defmodule Cortex.Conversations.TitleGenerator do
  @moduledoc "根据首条消息异步生成对话标题"

  alias Cortex.Config.SearchSettings
  alias Cortex.Config.LlmResolver
  alias Cortex.Conversations

  @system_prompt "Generate a concise title (max 6 words) for this conversation based on the user's first message. Reply with only the title, no punctuation."

  def maybe_generate(conversation, first_message) do
    settings = SearchSettings.get_settings()

    case settings.title_generation do
      :disabled ->
        :skip

      :conversation ->
        model_config = conversation.model_config || %{}
        Task.start(fn -> generate(conversation, first_message, model_config) end)

      :model ->
        model_name = settings.title_model
        Task.start(fn -> generate(conversation, first_message, %{model: model_name}) end)
    end
  end

  defp generate(conversation, first_message, model_config) do
    with {:ok, llm_opts} <- LlmResolver.resolve(model_config),
         {:ok, title} <- call_llm(llm_opts, first_message) do
      Conversations.update_conversation(conversation, %{title: title})
      emit_title_updated(conversation.id, title)
    end
  end

  defp call_llm(llm_opts, user_message) do
    # 使用 req_llm 发起单次非流式调用
    messages = [
      %{role: "system", content: @system_prompt},
      %{role: "user", content: user_message}
    ]
    # max_tokens: 20 控制成本
    ReqLLM.chat(llm_opts |> Map.put(:max_tokens, 20) |> Map.put(:stream, false), messages)
  end
end
```

### SearchSettings 新增字段

```elixir
field :title_generation, Ecto.Enum,
  values: [:disabled, :conversation, :model],
  default: :disabled

field :title_model, :string  # 仅 :model 模式使用
```

### UI 配置项（Search Settings 页面）

| 字段 | 类型 | 说明 |
|---|---|---|
| `title_generation` | select | disabled / conversation / model |
| `title_model` | text | 仅 mode=model 时显示，如 `gpt-4o-mini` |

### 触发点

`agent_loop.ex` 在 Agent 收到第一条用户消息后调用：

```elixir
# 仅在对话首条消息时触发（message_count == 1）
if message_count == 1 do
  TitleGenerator.maybe_generate(conversation, user_message)
end
```

### 信号

| 信号类型 | 时机 |
|---|---|
| `conversation.title.updated` | 标题生成成功后 |
| `conversation.title.failed` | LLM 调用失败（静默，不影响主流程） |

---

## 本期不包含

- 配置模板系统
- 配置回滚功能
- 多用户权限分级
- 配置变更审计日志 UI
