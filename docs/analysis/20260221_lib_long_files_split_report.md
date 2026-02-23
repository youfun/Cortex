# lib 目录超长文件拆分分析报告（2026-02-21）

## 范围与口径
- 范围：`lib/` 目录
- 口径：按行数统计，重点关注 `>= 400` 行的模块（经验阈值，超过该规模往往出现职责过载、测试困难、变更冲突频发）
- 目标：给出可执行的拆分方向（按职责、按领域、按渲染/业务分层）

## 超长文件清单（>= 400 行）
- 1402 `lib/cortex/bdd/instructions/v1.ex`
- 955 `lib/cortex/agents/llm_agent.ex`
- 767 `lib/cortex_web/live/helpers/agent_live_helpers.ex`
- 736 `lib/cortex/memory/knowledge_graph.ex`
- 719 `lib/cortex_web/live/components/jido_components.ex`
- 617 `lib/cortex/memory/subconscious.ex`
- 595 `lib/cortex/memory/proposal.ex`
- 548 `lib/cortex/memory/store.ex`
- 516 `lib/cortex_web/live/settings_live/channels.ex`
- 514 `lib/cortex_web/live/settings_live/channels_component.ex`
- 472 `lib/cortex_web/components/core_components.ex`
- 451 `lib/cortex/agents/compaction.ex`
- 434 `lib/cortex_web/live/jido_live.ex`
- 432 `lib/cortex/channels/telegram/poller.ex`
- 428 `lib/cortex/tools/handlers/read_structure.ex`
- 427 `lib/cortex/memory/observation.ex`

## 拆分建议（按文件）

**1) `lib/cortex/bdd/instructions/v1.ex`（1402 行）**
- 现状：单一模块里通过 `run!/5` 的巨型 case 覆盖大量 BDD 能力，几乎所有步骤逻辑聚集在一个文件。
- 风险：可读性极差、变更冲突频率高、测试颗粒过粗、扩展新步骤成本高。
- 建议拆分方向：
  - 拆成多个“能力域”模块，例如 `Cortex.BDD.Instructions.Signal`, `...Tool`, `...Memory`, `...Agent`, `...Session` 等。
  - `V1` 仅保留能力注册与路由分发（根据 `kind/name` 派发到子模块）。
  - 每个子模块提供 `capabilities/0` 与 `run/4`，在主模块聚合。

**2) `lib/cortex/agents/llm_agent.ex`（955 行）**
- 现状：单模块包含 Client API、GenServer 回调、信号订阅处理、上下文恢复、广播与权限等多职责。
- 风险：职责边界模糊，阅读成本高，改动易引入非预期副作用。
- 建议拆分方向：
  - `LLMAgent.API`（仅对外接口）
  - `LLMAgent.Server`（GenServer 回调与状态机）
  - `LLMAgent.SignalHandlers`（SignalHub 相关处理）
  - `LLMAgent.Context`（TapeContext/llm_context 处理）
  - 已存在的 `LLMAgent.ToolExecution`、`LLMAgent.LoopHandler` 可继续深化职责边界。

**3) `lib/cortex_web/live/helpers/agent_live_helpers.ex`（767 行）**
- 现状：合并了模型选择、会话切换、消息流、权限、UI 状态等多种 LiveView 逻辑。
- 风险：LiveView 交互逻辑耦合，难以定位问题与复用。
- 建议拆分方向：
  - `AgentLiveHelpers.Model`（模型解析与错误处理）
  - `AgentLiveHelpers.Conversation`（会话加载/切换/流）
  - `AgentLiveHelpers.Permissions`（权限 UI/状态）
  - `AgentLiveHelpers.Streaming`（流式消息与 plan 状态）

**4) `lib/cortex/memory/knowledge_graph.ex`（736 行）**
- 现状：节点/边结构、增删改查、衰减、强化、剪枝、扩散激活均在一个模块。
- 风险：算法/数据结构/信号耦合，修改高风险。
- 建议拆分方向：
  - `KnowledgeGraph.Node` / `KnowledgeGraph.Edge`（结构与操作）
  - `KnowledgeGraph.Mutation`（增删改）
  - `KnowledgeGraph.Dynamics`（decay/reinforce/spreading）
  - `KnowledgeGraph.Signals`（SignalHub 通知封装）

**5) `lib/cortex_web/live/components/jido_components.ex`（719 行）**
- 现状：大量 LiveView 组件/模板在一个文件，包含聊天面板、选择器、消息流等。
- 风险：模板难以维护，变更冲突多，组件难复用。
- 建议拆分方向：
  - 按 UI 区块拆分：`ChatPanel`, `AgentSelector`, `ModelSelector`, `MessageList`, `StreamingArea` 等。
  - 保留 `JidoComponents` 作为聚合入口或 alias 导出。

**6) `lib/cortex/memory/subconscious.ex`（617 行）**
- 现状：GenServer、信号处理、分析逻辑、去重、提议创建混在一起。
- 风险：高耦合，影响可测试性。
- 建议拆分方向：
  - `Subconscious.Server`（GenServer callbacks）
  - `Subconscious.SignalHandler`（signal routing）
  - `Subconscious.Analyzer`（内容分析与提议生成）
  - `Subconscious.Dedupe`（去重策略）

**7) `lib/cortex/memory/proposal.ex`（595 行）**
- 现状：结构体、校验、ETS 读写、业务操作、统计与索引集中。
- 风险：持久化策略和领域模型耦合。
- 建议拆分方向：
  - `Proposal`（结构体与构造）
  - `Proposal.Validation`（类型/状态校验）
  - `Proposal.Store`（ETS 读写与索引维护）

**8) `lib/cortex/memory/store.ex`（548 行）**
- 现状：GenServer + 文件持久化 + 观察项管理 + 提议接受 + 记忆整合混杂。
- 风险：文件 IO 和业务流程混合，易引入竞态与性能问题。
- 建议拆分方向：
  - `Memory.Store.Server`（GenServer 逻辑）
  - `Memory.Store.Persistence`（`MEMORY.md` 读写与解析）
  - `Memory.Store.Observation`（观察项 CRUD）
  - `Memory.Store.Proposal`（提议接受/转换）

**9) `lib/cortex_web/live/settings_live/channels.ex`（516 行）**
- 现状：LiveView 内包含多适配器参数解析与保存逻辑。
- 风险：新增渠道容易引入重复与错误。
- 建议拆分方向：
  - `Channels.ConfigParser`（按 adapter 映射参数）
  - `Channels.Settings`（保存/更新逻辑）
  - LiveView 保持 UI 事件与状态转发。

**10) `lib/cortex_web/live/settings_live/channels_component.ex`（514 行）**
- 现状：render 模板与保存逻辑混合，且与 `channels.ex` 重复。
- 风险：重复逻辑导致行为不一致。
- 建议拆分方向：
  - 抽离共享的配置解析与保存逻辑到 `Channels.Settings`。
  - 模板拆成 `DingtalkForm`, `FeishuForm`, `WecomForm`, `TelegramForm`, `DiscordForm` 子组件文件。

**11) `lib/cortex_web/components/core_components.ex`（472 行）**
- 现状：基础 UI 组件集中（Flash、Button、Form、Input、Table 等）。
- 风险：文件持续膨胀，改动冲突高。
- 建议拆分方向：
  - `CoreComponents.Flash`, `CoreComponents.Button`, `CoreComponents.Form`, `CoreComponents.Table` 等按组件族拆分。
  - 统一在 `CoreComponents` 里 re-export/alias。

**12) `lib/cortex/agents/compaction.ex`（451 行）**
- 现状：压缩策略、阈值判断、工具输出截断、LLM 摘要、telemetry/信号混合。
- 风险：策略调整影响过大，测试覆盖难。
- 建议拆分方向：
  - `Compaction.Policy`（阈值与策略选择）
  - `Compaction.Truncation`（工具输出截断）
  - `Compaction.Summarizer`（LLM 摘要）
  - `Compaction.Telemetry`（统计/信号）

**13) `lib/cortex_web/live/jido_live.ex`（434 行）**
- 现状：mount、事件处理、消息处理、UI 状态管理集中。
- 风险：LiveView 过载，迭代新功能风险大。
- 建议拆分方向：
  - `JidoLive.Mount`（初始化流程）
  - `JidoLive.Events`（handle_event 分组）
  - `JidoLive.Messages`（handle_info 分组）
  - 与 `AgentLiveHelpers` 的边界进一步清晰化。

**14) `lib/cortex/channels/telegram/poller.ex`（432 行）**
- 现状：轮询调度、更新解析、白名单校验、信号发布在一处。
- 风险：协议变更或新增消息类型不易扩展。
- 建议拆分方向：
  - `Telegram.Poller.Server`（轮询循环）
  - `Telegram.Poller.Parser`（update 解析与消息路由）
  - `Telegram.Poller.Auth`（allowlist 策略）

**15) `lib/cortex/tools/handlers/read_structure.ex`（428 行）**
- 现状：工具执行、文件读取、语言识别、AST/正则解析均在单文件。
- 风险：支持更多语言时会持续膨胀。
- 建议拆分方向：
  - `ReadStructure.Runner`（工具入口/信号）
  - `ReadStructure.Elixir`, `ReadStructure.JS`, `ReadStructure.Rust`, `ReadStructure.Python`, `ReadStructure.Go`（按语言拆分）
  - `ReadStructure.Fallback`（unsupported 或正则降级）

**16) `lib/cortex/memory/observation.ex`（427 行）**
- 现状：结构体、Markdown 序列化/解析、时间格式化都在一个模块。
- 风险：格式扩展不便，测试覆盖难。
- 建议拆分方向：
  - `Observation`（结构体/构造）
  - `Observation.Markdown`（序列化与解析）

## 拆分优先级建议
- 高优先级（频繁改动或职责极多）：`bdd/instructions/v1.ex`, `agents/llm_agent.ex`, `jido_live.ex`, `agent_live_helpers.ex`, `jido_components.ex`
- 中优先级（领域模块、算法复杂）：`memory/knowledge_graph.ex`, `memory/store.ex`, `memory/subconscious.ex`, `agents/compaction.ex`, `tools/handlers/read_structure.ex`
- 低优先级（相对稳定或可延期）：`core_components.ex`, `memory/proposal.ex`, `memory/observation.ex`, `channels/telegram/poller.ex`, `settings_live/channels*.ex`

## 说明
- 本报告仅基于 `lib/` 的行数与职责聚合度分析，未包含 `test/` 覆盖情况与调用依赖图。
- 若需实际拆分实施建议（模块边界与依赖关系图、迁移步骤），可以在此基础上进一步产出“拆分实施计划”。
