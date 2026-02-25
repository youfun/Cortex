# LLM 可配置设置系统规划 V2

**日期**: 2026-02-25
**版本**: V2（基于 V1 评审修订）
**目标**: 让 Agent 通过 tool call 修改所有设置页面的配置，实现 SNS 通道上的远程配置能力。

---

## V1 评审问题总结

| # | 问题 | 严重度 | V2 修正 |
|---|---|---|---|
| 1 | `Cortex.Config` 统一接口用 `@callback` 但无实现者，与现有 Context 模式不符 | 中 | 移除抽象 behaviour，各 Context 模块保持独立，通过 `GetSystemConfig` 聚合读取 |
| 2 | `ShellInterceptor` 只拦截 shell 命令，无法拦截 tool call | 高 | 在 `ToolRunner.execute/3` 中新增 `ToolInterceptor` 拦截层，支持按工具名审批 |
| 3 | `SearchExtension` 在两个计划中实现不一致（GenServer vs Extension） | 高 | 搜索核心由 Agent Search 计划负责，本计划只负责 `SearchSettings` schema 和配置工具 |
| 4 | `ConfigExtension` 概念与现有 Extension 机制不匹配 | 高 | 配置工具直接在 `SearchExtension.tools/0` 中注册，或通过独立的 `ConfigExtension` 注册，不监听信号 |
| 5 | 缺少对现有 `Config.Settings` 模块（`persistent_term`）的整合 | 中 | `SearchSettings` 用 DB 存储，但通过 `persistent_term` 缓存热路径读取 |
| 6 | `update_model_config` 工具与现有 `Config` context 重复 | 低 | 复用现有 `Config.update_llm_model/2` 和 `Config.Settings`，handler 只做薄封装 |
| 7 | 审批流程中 `permission.request` 信号的完整生命周期未说明 | 中 | 补充 `ToolInterceptor` → `PermissionTracker` → `ToolRunner` 的完整流程 |

---

## 核心设计原则

### 1. 薄 Handler + 复用现有 Context

配置工具的 Handler 只做参数校验和信号发射，实际 DB 操作复用现有 Context：

```
update_channel_config handler → Cortex.Channels.update_channel_config/2
update_model_config handler   → Cortex.Config.update_llm_model/2 + Config.Settings
update_search_config handler  → Cortex.Config.SearchSettings.update_settings/1
get_system_config handler     → 聚合读取各 Context
```

### 2. 工具注册策略

配置工具通过 `ConfigExtension`（Extension behaviour）注册：

| 工具名 | 配置域 | 复用的 Context |
|---|---|---|
| `update_channel_config` | Channels | `Cortex.Channels` |
| `update_model_config` | Models | `Cortex.Config` + `Config.Settings` |
| `update_search_config` | Search | `Cortex.Config.SearchSettings`（新建） |
| `get_system_config` | 全局 | 聚合读取 |

### 3. 审批拦截（ToolInterceptor）

当前 `ToolRunner.execute/3` 直接调用 `tool.module.execute/2`，没有审批机制。V2 新增 `ToolInterceptor` 模块：

```elixir
# 在 ToolRunner.execute/3 中插入拦截检查
def execute(tool_name, args, ctx) do
  case Registry.get(tool_name) do
    {:ok, tool} ->
      case ToolInterceptor.check(tool_name, args) do
        :ok ->
          # 正常执行
          do_execute(tool, args, ctx)

        {:approval_required, reason} ->
          # 返回等待审批状态，由 LlmAgent 处理
          {:error, {:approval_required, reason}}
      end

    :error ->
      {:error, :tool_not_found, 0}
  end
end
```

---

## 架构分层

```
Agent (tool call: update_search_config)
    │
    ▼
ToolRunner.execute/3
    │
    ├── ToolInterceptor.check/2          ← 新增：审批拦截
    │       │
    │       └── {:approval_required, reason}
    │               │
    │               ▼
    │           LlmAgent 发射 permission.request 信号
    │               │
    │               ▼
    │           UI/SNS 显示审批请求
    │               │
    │               ▼
    │           permission.resolved → 重新执行
    │
    └── tool.module.execute/2            ← 正常执行路径
            │
            ▼
        Cortex.Config.SearchSettings.update_settings/1  ← Context 层
            │
            ▼
        SignalHub.emit("config.search.updated")         ← 通知订阅者
            │
            └─→ LiveView PubSub 刷新 UI
```

---

## 文件结构

```
lib/cortex/
├── config/
│   └── search_settings.ex              # SearchSettings schema + context（新建）
├── tools/
│   ├── tool_interceptor.ex             # 工具级审批拦截器（新建）
│   ├── tool_runner.ex                  # 修改：集成 ToolInterceptor
│   └── handlers/
│       ├── update_channel_config.ex    # 薄 handler → Channels context
│       ├── update_model_config.ex      # 薄 handler → Config context
│       ├── update_search_config.ex     # 薄 handler → SearchSettings context
│       └── get_system_config.ex        # 聚合读取
├── extensions/
│   └── config_extension.ex             # ConfigExtension（注册配置工具）
├── search/
│   └── config_watcher.ex              # GenServer：监听 config.search.updated，重载 provider
└── signal_catalog.ex                   # 添加 config.*.updated 信号常量

lib/cortex_web/live/settings_live/
├── index.ex                            # 修改：添加 :search action 和 tab
└── search_component.ex                 # 新建：Search 配置 LiveComponent

priv/repo/migrations/
└── YYYYMMDDHHMMSS_create_search_settings.exs
```

---

## 实现细节

### 1. SearchSettings Schema

```elixir
defmodule Cortex.Config.SearchSettings do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Cortex.Repo

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

  def get_settings do
    case Repo.one(from(s in __MODULE__, limit: 1)) do
      nil -> %__MODULE__{}
      settings -> settings
    end
  end

  def update_settings(attrs) do
    get_settings()
    |> changeset(attrs)
    |> Repo.insert_or_update()
  end
end
```

### 2. ToolInterceptor（新模块）

```elixir
defmodule Cortex.Tools.ToolInterceptor do
  @moduledoc """
  工具级审批拦截器。
  与 ShellInterceptor 平行，但拦截的是 tool call 而非 shell 命令。
  """

  @approval_required_tools ~w(update_channel_config update_model_config update_search_config)

  def check(tool_name, _args) when tool_name in @approval_required_tools do
    {:approval_required, "Configuration change '#{tool_name}' requires user approval"}
  end

  def check(_tool_name, _args), do: :ok
end
```

### 3. UpdateSearchConfig Handler（薄封装）

```elixir
defmodule Cortex.Tools.Handlers.UpdateSearchConfig do
  @behaviour Cortex.Tools.ToolBehaviour

  alias Cortex.Config.SearchSettings
  alias Cortex.SignalHub

  @impl true
  def execute(args, ctx) do
    old_settings = SearchSettings.get_settings()

    case SearchSettings.update_settings(args) do
      {:ok, new_settings} ->
        SignalHub.emit("config.search.updated", %{
          provider: "config",
          event: "search",
          action: "updated",
          actor: "llm_agent",
          origin: %{
            channel: "tool",
            client: "config_handler",
            platform: "server",
            session_id: Map.get(ctx, :session_id)
          },
          old_value: Map.from_struct(old_settings) |> Map.drop([:__meta__]),
          new_value: Map.from_struct(new_settings) |> Map.drop([:__meta__])
        }, source: "/tool/config")

        {:ok, "Search configuration updated successfully."}

      {:error, changeset} ->
        {:error, "Failed to update: #{inspect(changeset.errors)}"}
    end
  end
end
```

### 4. UpdateChannelConfig Handler（复用现有 Context）

```elixir
defmodule Cortex.Tools.Handlers.UpdateChannelConfig do
  @behaviour Cortex.Tools.ToolBehaviour

  alias Cortex.Channels
  alias Cortex.SignalHub

  @impl true
  def execute(args, ctx) do
    adapter = Map.get(args, :adapter) || Map.get(args, "adapter")
    enabled = Map.get(args, :enabled)
    config = Map.get(args, :config) || Map.get(args, "config", %{})

    attrs = %{adapter: adapter, enabled: enabled, config: config}
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()

    result = case Channels.get_channel_config_by_adapter(adapter) do
      nil ->
        Channels.create_channel_config(attrs)
      existing ->
        Channels.update_channel_config(existing, attrs)
    end

    case result do
      {:ok, _config} ->
        SignalHub.emit("config.channel.updated", %{
          provider: "config",
          event: "channel",
          action: "updated",
          actor: "llm_agent",
          origin: %{
            channel: "tool",
            client: "config_handler",
            platform: "server",
            session_id: Map.get(ctx, :session_id)
          },
          adapter: adapter
        }, source: "/tool/config")

        {:ok, "Channel '#{adapter}' configuration updated."}

      {:error, changeset} ->
        {:error, "Failed to update channel: #{inspect(changeset.errors)}"}
    end
  end
end
```

### 5. UpdateModelConfig Handler（复用现有 Context）

```elixir
defmodule Cortex.Tools.Handlers.UpdateModelConfig do
  @behaviour Cortex.Tools.ToolBehaviour

  alias Cortex.Config
  alias Cortex.Config.Settings
  alias Cortex.SignalHub

  @impl true
  def execute(args, ctx) do
    model_name = Map.get(args, :model_name) || Map.get(args, "model_name")
    action = Map.get(args, :action) || Map.get(args, "action", "update")

    result = case action do
      "enable" -> Settings.enable_model(model_name)
      "disable" -> Settings.disable_model(model_name)
      "set_default" -> Settings.set_skill_default_model(model_name)
      "update" ->
        case Config.get_llm_model_by_name(model_name) do
          nil -> {:error, :not_found}
          model ->
            attrs = Map.drop(args, [:model_name, :action, "model_name", "action"])
            Config.update_llm_model(model, attrs)
        end
    end

    case result do
      {:ok, _} ->
        SignalHub.emit("config.model.updated", %{
          provider: "config",
          event: "model",
          action: "updated",
          actor: "llm_agent",
          origin: %{
            channel: "tool",
            client: "config_handler",
            platform: "server",
            session_id: Map.get(ctx, :session_id)
          },
          model_name: model_name,
          model_action: action
        }, source: "/tool/config")

        {:ok, "Model '#{model_name}' #{action} completed."}

      {:error, :not_found} ->
        {:error, "Model '#{model_name}' not found."}

      {:error, changeset} ->
        {:error, "Failed: #{inspect(changeset.errors)}"}
    end
  end
end
```

### 6. GetSystemConfig Handler

```elixir
defmodule Cortex.Tools.Handlers.GetSystemConfig do
  @behaviour Cortex.Tools.ToolBehaviour

  alias Cortex.Channels
  alias Cortex.Config
  alias Cortex.Config.Settings

  @impl true
  def execute(args, _ctx) do
    domain = Map.get(args, :domain) || Map.get(args, "domain", "all")

    result = case domain do
      "channels" -> %{channels: get_channels_config()}
      "models" -> %{models: get_models_config()}
      "search" -> %{search: get_search_config()}
      "all" -> %{
        channels: get_channels_config(),
        models: get_models_config(),
        search: get_search_config()
      }
      _ -> %{error: "Unknown domain: #{domain}"}
    end

    {:ok, Jason.encode!(result, pretty: true)}
  end

  defp get_channels_config do
    Channels.list_channel_configs()
    |> Enum.map(fn c ->
      %{adapter: c.adapter, enabled: c.enabled}
    end)
  end

  defp get_models_config do
    %{
      default_model: Settings.get_skill_default_model(),
      available_models: Settings.list_available_models()
        |> Enum.map(fn m -> %{name: m.name, provider: m.provider_drive, enabled: m.enabled} end)
    }
  end

  defp get_search_config do
    try do
      settings = Cortex.Config.SearchSettings.get_settings()
      %{
        default_provider: settings.default_provider,
        brave_api_key: mask_key(settings.brave_api_key),
        tavily_api_key: mask_key(settings.tavily_api_key),
        enable_llm_title_generation: settings.enable_llm_title_generation
      }
    rescue
      _ -> %{status: "not_configured"}
    end
  end

  defp mask_key(nil), do: nil
  defp mask_key(""), do: nil
  defp mask_key(key) when byte_size(key) <= 4, do: "****"
  defp mask_key(key), do: String.slice(key, 0, 4) <> "****"
end
```

### 7. ConfigExtension

```elixir
defmodule Cortex.Extensions.ConfigExtension do
  @behaviour Cortex.Extensions.Extension

  def name, do: "config"
  def description, do: "LLM-accessible configuration tools for channels, models, and search"
  def hooks, do: []

  def tools do
    [
      %Cortex.Tools.Tool{
        name: "update_channel_config",
        description: "Update SNS channel configuration (Telegram, Feishu, Discord, etc.).",
        parameters: [
          adapter: [type: :string, required: true, doc: "Channel adapter: telegram | feishu | discord | dingtalk | wecom"],
          enabled: [type: :boolean, required: false, doc: "Enable or disable this channel"],
          config: [type: :map, required: false, doc: "Channel-specific config map"]
        ],
        module: Cortex.Tools.Handlers.UpdateChannelConfig
      },
      %Cortex.Tools.Tool{
        name: "update_model_config",
        description: "Update LLM model configuration (enable/disable, set default).",
        parameters: [
          model_name: [type: :string, required: true, doc: "Model name"],
          action: [type: :string, required: false, doc: "Action: enable | disable | set_default | update (default: update)"]
        ],
        module: Cortex.Tools.Handlers.UpdateModelConfig
      },
      %Cortex.Tools.Tool{
        name: "update_search_config",
        description: "Update web search configuration (default provider, API keys).",
        parameters: [
          default_provider: [type: :string, required: false, doc: "Default search provider: brave | tavily"],
          brave_api_key: [type: :string, required: false, doc: "Brave Search API key"],
          tavily_api_key: [type: :string, required: false, doc: "Tavily Search API key"],
          enable_llm_title_generation: [type: :boolean, required: false, doc: "Enable LLM-generated titles"]
        ],
        module: Cortex.Tools.Handlers.UpdateSearchConfig
      },
      %Cortex.Tools.Tool{
        name: "get_system_config",
        description: "Read current system configuration (channels, models, search).",
        parameters: [
          domain: [type: :string, required: false, doc: "Config domain: channels | models | search | all (default: all)"]
        ],
        module: Cortex.Tools.Handlers.GetSystemConfig
      }
    ]
  end

  def init(_config), do: {:ok, %{}}
end
```

### 8. SearchConfigWatcher（独立 GenServer）

```elixir
defmodule Cortex.Search.ConfigWatcher do
  @moduledoc """
  监听 config.search.updated 信号，重新加载搜索 provider 配置。
  独立于 Extension 生命周期，由 Application supervisor 管理。
  """
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Cortex.SignalHub.subscribe("config.search.updated")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:signal, %Jido.Signal{type: "config.search.updated"}}, state) do
    # 清除 persistent_term 缓存，下次读取时从 DB 重新加载
    :persistent_term.erase({Cortex.Config.SearchSettings, :cached})
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}
end
```

---

## ToolRunner 修改

在 `ToolRunner.execute/3` 中集成 `ToolInterceptor`：

```elixir
# tool_runner.ex 修改点
def execute(tool_name, args, ctx) do
  case Registry.get(tool_name) do
    {:ok, tool} ->
      # 新增：工具级审批检查
      case Cortex.Tools.ToolInterceptor.check(tool_name, args) do
        :ok ->
          normalized_args = normalize_args(args)
          # ... 现有执行逻辑不变

        {:approval_required, reason} ->
          {:error, {:approval_required, reason}, 0}
      end

    :error ->
      {:error, :tool_not_found, 0}
  end
end
```

---

## 权限控制

### 审批完整流程

```
1. Agent 调用 update_search_config
2. ToolRunner → ToolInterceptor.check → {:approval_required, reason}
3. ToolRunner 返回 {:error, {:approval_required, reason}, 0}
4. LlmAgent.ToolExecution 检测到 :approval_required
5. 发射 permission.request 信号（复用现有 PermissionTracker）
6. UI/SNS 显示审批请求
7. 用户批准 → permission.resolved 信号
8. LlmAgent 重新调用 ToolRunner.execute（此时跳过审批，因为已有 permission token）
```

**注意**：审批 token 机制需要在 `ToolInterceptor` 中支持 `ctx` 中的 `approved_tools` 字段：

```elixir
def check(tool_name, _args, ctx) when tool_name in @approval_required_tools do
  if tool_name in Map.get(ctx, :approved_tools, []) do
    :ok
  else
    {:approval_required, "Configuration change '#{tool_name}' requires user approval"}
  end
end
```

---

## 信号集成

| 信号类型 | 时机 | payload 关键字段 |
|---|---|---|
| `config.channel.updated` | Channel 配置变更 | `adapter` |
| `config.model.updated` | Model 配置变更 | `model_name`, `model_action` |
| `config.search.updated` | Search 配置变更 | `old_value`, `new_value` |

`get_system_config` 是只读操作，不发射信号（遵循 AGENTS.md "读操作不发射信号" 原则）。

---

## UI 变更

### Settings 页面添加 Search tab

修改 `SettingsLive.Index`：

```elixir
# 新增 apply_action
defp apply_action(socket, :search, _params) do
  assign(socket, :page_title, "Search Settings")
end

# render 中添加 tab 和 component
<.link patch={~p"/settings/search"} class={[...]}>
  <.icon name="hero-magnifying-glass" class="w-5 h-5" />
  <span class="text-sm font-medium">Search</span>
</.link>

# content area
<% :search -> %>
  <.live_component
    module={CortexWeb.SettingsLive.SearchComponent}
    id="search-settings"
  />
```

---

## 实施任务（DAG）

```
=== 配置工具核心 ===
T1: SearchSettings schema + migration (config/search_settings.ex)
T2: ToolInterceptor 模块 (tools/tool_interceptor.ex)
T3: ToolRunner 集成 ToolInterceptor (tools/tool_runner.ex 修改)     ← 依赖 T2
T4: UpdateSearchConfig handler                                      ← 依赖 T1
T5: UpdateChannelConfig handler（复用 Channels context）
T6: UpdateModelConfig handler（复用 Config context）
T7: GetSystemConfig handler                                         ← 依赖 T1
T8: ConfigExtension（注册 T4-T7 的工具）                              ← 依赖 T4-T7
T9: SearchConfigWatcher GenServer                                    ← 依赖 T1
T10: SearchComponent LiveView                                        ← 依赖 T1
T11: SettingsLive.Index 添加 Search tab + Router                     ← 依赖 T10
T12: application.ex 加载 ConfigExtension + SearchConfigWatcher       ← 依赖 T8, T9
T13: LlmAgent.ToolExecution 处理 :approval_required                  ← 依赖 T3

=== 自动标题生成 ===
T15: Config.Settings 扩展 title_generation/title_model 设置          ← 独立
T16: TitleGenerator 模块 (conversations/title_generator.ex)          ← 依赖 T15
T17: agent_live_helpers.ex 集成首条消息检测 + 触发                    ← 依赖 T16
T18: UI 添加标题生成配置项（SearchComponent 或 GeneralComponent）     ← 依赖 T15

=== 测试 ===
T14: 配置工具测试                                                    ← 依赖 T1-T13
T19: 标题生成测试                                                    ← 依赖 T16, T17

依赖图：
T1 → T4, T7, T9, T10
T2 → T3 → T13
T4, T5, T6, T7 → T8 → T12
T9 → T12
T10 → T11
T15 → T16 → T17
T15 → T18
```

---

## BDD 场景

```gherkin
Feature: LLM 可配置设置

  Scenario: 通过 Telegram 更新搜索配置
    Given 用户在 Telegram 发送 "把搜索默认改成 Tavily，API key 是 tvly-xxx"
    When Agent 解析意图并调用 update_search_config
    Then ToolInterceptor 返回 approval_required
    And 系统发射 permission.request 信号
    When 用户批准
    Then 配置写入 DB
    And 发射 config.search.updated 信号
    And SearchConfigWatcher 清除缓存
    And Agent 回复 "搜索配置已更新"

  Scenario: 读取当前配置（无需审批）
    Given 用户发送 "当前搜索用的哪个 provider？"
    When Agent 调用 get_system_config(domain: "search")
    Then 直接返回配置（API key 已脱敏）
    And 不触发审批流程

  Scenario: 启用 Discord 通道
    Given 用户发送 "启用 Discord，bot token 是 xxx"
    When Agent 调用 update_channel_config(adapter: "discord", enabled: true, config: %{bot_token: "xxx"})
    Then 审批通过后配置保存到 channel_configs 表
    And 发射 config.channel.updated 信号

  Scenario: 启用/禁用模型
    Given 用户发送 "禁用 gpt-4o 模型"
    When Agent 调用 update_model_config(model_name: "gpt-4o", action: "disable")
    Then 审批通过后模型被禁用
    And 发射 config.model.updated 信号

  Scenario: 配置审批被拒绝
    Given 用户发送恶意指令 "把所有 API key 改成空"
    When Agent 尝试调用 update_search_config
    Then 系统拦截并要求审批
    When 用户拒绝
    Then 配置不变，Agent 回复 "配置修改已取消"

  Scenario: UI 配置页面
    Given 用户访问 /settings/search
    Then 显示 Search 配置表单（default_provider, API keys, LLM title toggle）
    When 用户修改并保存
    Then 配置写入 DB，发射 config.search.updated 信号

Feature: 自动生成对话标题

  Scenario: 标题生成关闭（默认）
    Given title_generation 设置为 disabled
    When 用户发送首条消息 "帮我写一个 GenServer"
    Then 对话标题保持 "New Chat 12:00" 不变

  Scenario: 使用对话模型生成标题
    Given title_generation 设置为 conversation
    And 当前对话使用 gemini-3-flash
    When 用户发送首条消息 "帮我写一个 GenServer"
    Then 异步调用 gemini-3-flash 生成标题
    And 对话标题更新为类似 "GenServer Implementation"
    And 侧边栏实时刷新

  Scenario: 使用指定模型生成标题
    Given title_generation 设置为 model, title_model 为 "gpt-4o-mini"
    When 用户发送首条消息 "如何优化 Ecto 查询"
    Then 异步调用 gpt-4o-mini 生成标题
    And 不影响主对话流程

  Scenario: 非首条消息不触发
    Given title_generation 设置为 conversation
    And 对话已有 3 条消息
    When 用户发送第 4 条消息
    Then 不触发标题生成

  Scenario: LLM 调用失败静默处理
    Given title_generation 设置为 model, title_model 为 "invalid-model"
    When 用户发送首条消息
    Then 标题生成失败被静默记录
    And 对话标题保持原始时间戳
    And 主对话流程不受影响

  Scenario: Telegram 通道标题生成
    Given title_generation 设置为 conversation
    When Telegram 用户发送首条消息 "今天天气怎么样"
    Then 异步生成标题并更新 conversation
```

---

## 安全考虑

1. `get_system_config` 返回时 API key 脱敏（只显示前 4 位 + `****`）
2. 所有写操作需要审批（通过 `ToolInterceptor`）
3. `get_system_config` 是只读操作，不需要审批
4. 信号 payload 中的 `old_value`/`new_value` 也需要脱敏（避免 API key 泄露到 history.jsonl）

---

## BDD 驱动迭代流程说明

本计划遵循 BDD 驱动的任务迭代流程（参考 `.agent/skills/bddc/SKILL.md`）：

1. **规划阶段**（当前）：完成架构分析、任务 DAG 和 BDD 场景定义
2. **BDD 编译**：将上述 Gherkin 场景通过 `bddc` 编译为 ExUnit 测试骨架
3. **红灯实现**：运行测试确认全部失败（红灯）
4. **绿灯实现**：按 DAG 顺序逐任务实现，每完成一个任务运行测试
5. **重构**：所有测试通过后进行代码清理

---

## 自动生成对话标题

### 背景

当前对话标题由 `agent_live_helpers.ex:489` 的 `new_conversation_title/1` 生成静态时间戳（如 `"New Chat 12:00"`），对用户无意义。需要通过 LLM 根据首条消息自动生成语义化标题。

### V1 设计问题分析

| # | V1 问题 | V2 修正 |
|---|---|---|
| 1 | 标题配置放在 `SearchSettings` 中，语义不匹配 | 新建 `Cortex.Config.GeneralSettings` schema，或扩展现有 `Config.Settings`（`persistent_term`）增加标题相关设置 |
| 2 | 触发点在 `agent_loop.ex`，但该模块无 conversation 对象和 message count | 触发点改为 `dispatch_chat_request` 所在的 `agent_live_helpers.ex`，此处有 `conversation_id` 和 `socket.assigns` |
| 3 | 使用不存在的 `ReqLLM.chat` API | 使用现有 `Cortex.LLM.Client.complete/3`（非流式单次调用） |
| 4 | `LlmResolver.resolve/1` 用于标题生成过于重量级 | 直接用 `Client.complete(model_name, prompt)` 即可 |
| 5 | 缺少"首条消息"判断机制 | 通过 `Conversations.load_display_messages/2` 检查消息数量，或在 conversation 创建时设置 `title_generated: false` 标记 |
| 6 | SNS 通道（Telegram/Feishu）的触发点未覆盖 | Telegram `command_handler.ex:98` 和 Feishu 也创建 conversation，需统一触发 |

### 三种模式

| 模式 | 配置值 | 行为 |
|---|---|---|
| 关闭 | `title_generation: :disabled` | 保持现有时间戳逻辑（默认） |
| 指定模型 | `title_generation: :model, title_model: "gpt-4o-mini"` | 使用指定的轻量模型生成 |
| 对话模型 | `title_generation: :conversation` | 复用当前对话的 LLM 模型 |

### 配置存储

标题生成是全局设置，不属于搜索配置。两种方案：

**方案 A（推荐）：扩展 `Config.Settings` 的 `persistent_term`**

```elixir
# 在 Config.Settings 中新增
@default_settings %{
  "skill_default_model" => "gemini-3-flash",
  "title_generation" => "disabled",      # disabled | conversation | model
  "title_model" => nil,                  # 仅 :model 模式使用
  ...
}

def get_title_generation, do: get_global_setting("title_generation") || "disabled"
def get_title_model, do: get_global_setting("title_model")
def set_title_generation(mode), do: set_global_setting("title_generation", mode)
def set_title_model(model), do: set_global_setting("title_model", model)
```

优点：无需新建 schema/migration，与现有 Settings 模式一致。
缺点：`persistent_term` 重启后丢失，需要在 `application.ex` 中从 DB 或 config 恢复。

**方案 B：在 `SearchSettings` migration 中附带 title 字段**

如果 `SearchSettings` 已经需要新建 schema + migration，可以将 title 字段一并放入，避免多一个 migration。语义上不完美但实用。

### 实现模块

```elixir
defmodule Cortex.Conversations.TitleGenerator do
  @moduledoc "根据首条消息异步生成对话标题"

  require Logger

  alias Cortex.Config.Settings
  alias Cortex.Conversations
  alias Cortex.LLM.Client

  @system_prompt "Generate a concise title (max 6 words) for this conversation. Reply with only the title, no quotes or punctuation."

  @doc """
  在首条用户消息发送后异步触发标题生成。
  调用方需确保只在首条消息时调用。
  """
  def maybe_generate(conversation_id, first_message, model_name \\ nil) do
    mode = Settings.get_title_generation()

    case mode do
      "disabled" ->
        :skip

      "conversation" ->
        # 使用当前对话的模型
        effective_model = model_name || Settings.get_effective_skill_default_model()
        async_generate(conversation_id, first_message, effective_model)

      "model" ->
        # 使用指定的轻量模型
        title_model = Settings.get_title_model() || Settings.get_effective_skill_default_model()
        async_generate(conversation_id, first_message, title_model)

      _ ->
        :skip
    end
  end

  defp async_generate(conversation_id, first_message, model_name) do
    Task.Supervisor.start_child(Cortex.AgentTaskSupervisor, fn ->
      generate(conversation_id, first_message, model_name)
    end)
  end

  defp generate(conversation_id, first_message, model_name) do
    prompt = "#{@system_prompt}\n\nUser message: #{String.slice(first_message, 0, 200)}"

    case Client.complete(model_name, prompt, max_tokens: 20) do
      {:ok, title} when is_binary(title) and title != "" ->
        clean_title = title |> String.trim() |> String.slice(0, 50)

        case Conversations.get_conversation(conversation_id) do
          nil -> :ok
          conversation -> Conversations.update_conversation(conversation, %{title: clean_title})
        end

      {:ok, _} ->
        Logger.debug("[TitleGenerator] Empty title response, skipping")

      {:error, reason} ->
        Logger.warning("[TitleGenerator] Failed to generate title: #{inspect(reason)}")
    end
  end
end
```

### 触发点

**Web UI（`agent_live_helpers.ex`）**：

在 `dispatch_chat_request/2` 中，检测是否为首条消息并触发：

```elixir
defp dispatch_chat_request(socket, final_content) do
  # 现有信号发射逻辑不变...

  # 首条消息时触发标题生成
  maybe_trigger_title_generation(socket, final_content)

  socket
end

defp maybe_trigger_title_generation(socket, content) do
  conversation_id = socket.assigns.current_conversation_id
  model_name = get_current_model_name(socket)

  # 检查是否为首条用户消息（排除 system welcome message）
  case Conversations.load_display_messages(conversation_id, limit: 3) do
    messages when length(messages) <= 1 ->
      # 只有 welcome message 或空，说明这是首条用户消息
      Cortex.Conversations.TitleGenerator.maybe_generate(conversation_id, content, model_name)
    _ ->
      :ok
  end
end
```

**SNS 通道（Telegram/Feishu）**：

SNS 通道通过 `Conversations.create_conversation/2` 创建对话时已设置标题。首条消息触发可以通过监听 `agent.chat.request` 信号实现，或在各 dispatcher 中直接调用。

推荐方案：在 `Conversations.create_conversation/2` 返回后，由调用方在首条消息时调用 `TitleGenerator.maybe_generate/3`。

### UI 配置项

在 Settings 页面（可以放在 Search tab 或新建 General tab）添加：

| 字段 | 类型 | 说明 |
|---|---|---|
| `title_generation` | select | disabled / conversation / model |
| `title_model` | text | 仅 mode=model 时显示，如 `gpt-4o-mini` |

### 信号

不新增信号。标题更新通过 `Conversations.update_conversation/2` 完成，该函数已发射 `conversation.updated` 信号，LiveView 可通过 PubSub 订阅刷新侧边栏。

### 更新后的 DAG

在原有 DAG 基础上新增：

```
T15: Config.Settings 扩展 title_generation/title_model 设置     ← 独立
T16: TitleGenerator 模块 (conversations/title_generator.ex)     ← 依赖 T15
T17: agent_live_helpers.ex 集成首条消息检测 + 触发               ← 依赖 T16
T18: SearchComponent/GeneralComponent UI 添加标题配置项          ← 依赖 T15
T19: 测试（标题生成三种模式 + 首条消息检测）                      ← 依赖 T16, T17
```

### BDD 场景

```gherkin
Feature: 自动生成对话标题

  Scenario: 标题生成关闭（默认）
    Given title_generation 设置为 disabled
    When 用户发送首条消息 "帮我写一个 GenServer"
    Then 对话标题保持 "New Chat 12:00" 不变

  Scenario: 使用对话模型生成标题
    Given title_generation 设置为 conversation
    And 当前对话使用 gemini-3-flash
    When 用户发送首条消息 "帮我写一个 GenServer"
    Then 异步调用 gemini-3-flash 生成标题
    And 对话标题更新为类似 "GenServer Implementation"
    And 侧边栏实时刷新

  Scenario: 使用指定模型生成标题
    Given title_generation 设置为 model, title_model 为 "gpt-4o-mini"
    When 用户发送首条消息 "如何优化 Ecto 查询"
    Then 异步调用 gpt-4o-mini 生成标题
    And 不影响主对话流程

  Scenario: 非首条消息不触发
    Given title_generation 设置为 conversation
    And 对话已有 3 条消息
    When 用户发送第 4 条消息
    Then 不触发标题生成

  Scenario: LLM 调用失败静默处理
    Given title_generation 设置为 model, title_model 为 "invalid-model"
    When 用户发送首条消息
    Then 标题生成失败被静默记录
    And 对话标题保持原始时间戳
    And 主对话流程不受影响

  Scenario: Telegram 通道标题生成
    Given title_generation 设置为 conversation
    When Telegram 用户发送首条消息 "今天天气怎么样"
    Then 异步生成标题并更新 conversation
```

---

## 本期不包含

- 配置模板系统（`apply_config_template`）
- 配置回滚功能（`rollback_config`）
- 多用户权限分级
- 配置变更审计日志 UI
- 信号 payload 自动脱敏中间件（手动脱敏）
- 标题生成的多语言 prompt 优化（当前使用英文 prompt，对中文消息也能工作）
