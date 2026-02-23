# lib 超长文件拆分优化计划（2026-02-21）

基于 `docs/analysis/20260221_lib_long_files_split_report.md` 的逐文件审查结果。

---

## 一、评审结论总览

| # | 文件 | 行数 | 拆分合理？ | 理由 |
|---|------|------|-----------|------|
| 1 | `bdd/instructions/v1.ex` | 1402 | ✅ 合理 | 用户已自行处理，跳过 |
| 2 | `agents/llm_agent.ex` | 955 | ✅ 合理 | 已有4个子模块，但主文件仍承载过多信号处理 |
| 3 | `agent_live_helpers.ex` | 767 | ✅ 合理 | 混合了模型/会话/流式/权限/上下文5类职责 |
| 4 | `memory/knowledge_graph.ex` | 736 | ⚠️ 部分合理 | 纯数据结构+算法，内聚性尚可；仅建议抽离 Dynamics |
| 5 | `jido_components.ex` | 719 | ✅ 合理 | 6个独立UI区块混在一起，按组件拆分收益明显 |
| 6 | `memory/subconscious.ex` | 617 | ✅ 合理 | GenServer+信号+分析+中文NLP+提议创建，职责过多 |
| 7 | `memory/proposal.ex` | 595 | ❌ 不合理 | 单一领域模型+ETS操作，内聚性好，拆分反增复杂度 |
| 8 | `memory/store.ex` | 548 | ⚠️ 部分合理 | GenServer+文件IO+业务混合，但仅建议抽离持久化层 |
| 9 | `settings_live/channels.ex` | 516 | ✅ 合理（与10合并处理） | 与 channels_component.ex 大量重复代码 |
| 10 | `settings_live/channels_component.ex` | 514 | ✅ 合理（与9合并处理） | 同上，两文件应合并去重后再按表单拆分 |
| 11 | `core_components.ex` | 472 | ❌ 不合理 | Phoenix 生成器标准模式，组件间无耦合，拆分无收益 |
| 12 | `agents/compaction.ex` | 451 | ❌ 不合理 | 策略/截断/摘要/遥测是紧密流水线，拆分破坏可读性 |
| 13 | `jido_live.ex` | 434 | ⚠️ 部分合理 | LiveView 主模块，handle_event/handle_info 已较清晰；仅建议抽离 mount 初始化 |
| 14 | `telegram/poller.ex` | 432 | ❌ 不合理 | 轮询/解析/鉴权是单一流程的三阶段，内聚性好 |
| 15 | `tools/handlers/read_structure.ex` | 428 | ✅ 合理 | 按语言的解析器天然独立，新增语言会持续膨胀 |
| 16 | `memory/observation.ex` | 427 | ❌ 不合理 | 结构体+Markdown序列化是同一关注点，拆分无意义 |

### 统计

- 合理需拆分：7个文件（#2, #3, #5, #6, #9+#10, #15）
- 部分合理（小幅抽离）：3个文件（#4, #8, #13）
- 不合理（不建议拆分）：5个文件（#7, #11, #12, #14, #16）

---

## 二、不合理拆分的详细理由

### `memory/proposal.ex`（595行）— 不拆
报告建议拆为 Proposal / Proposal.Validation / Proposal.Store 三个模块。但实际审查发现：
- 结构体定义、类型校验、ETS 读写都围绕同一个 Proposal 实体
- 所有 public API（create/accept/reject/defer/get/list_pending/stats）都是对同一 ETS 表的 CRUD
- 校验逻辑（parse_type/parse_status）仅十几行 defp，不值得独立模块
- 拆分后调用方需要 alias 3个模块来完成一个操作，增加认知负担

### `core_components.ex`（472行）— 不拆
- 这是 Phoenix 生成器的标准产物，社区惯例就是单文件
- 每个组件（flash/button/input/table/header/list/icon）都是独立的 `def` + HEEx 模板，无相互依赖
- 472行对于组件库来说很正常，且增长缓慢
- 拆分后 `use CortexWeb` 的 import 链会变复杂

### `agents/compaction.ex`（451行）— 不拆
- maybe_compact → compact → force_drop → truncate_tool_outputs 是一条完整的压缩流水线
- 策略选择、截断、摘要、遥测是同一操作的不同阶段，拆分会破坏流程可读性
- 451行对于一个完整的压缩策略模块来说是合理的规模

### `telegram/poller.ex`（432行）— 不拆
- GenServer 轮询 → 解析 update → 鉴权 → 发射信号，是单一职责的线性流程
- dispatch_text_message 虽然较长（~80行），但它处理的是 Telegram 消息到信号的映射，逻辑内聚
- 432行对于一个完整的 Telegram 集成模块来说合理

### `memory/observation.ex`（427行）— 不拆
- 结构体 + Markdown 序列化/解析是同一领域对象的两面
- 报告建议拆出 `Observation.Markdown`，但序列化逻辑与结构体定义紧密耦合
- 427行中大量是 defp 辅助函数（parse_priority/parse_timestamp 等），拆分无收益

---

## 三、合理拆分的实施计划

### 优先级 P0：高频改动 + 职责严重过载

#### 3.1 `agents/llm_agent.ex`（955行）→ 抽离信号处理

现状：已有 `ToolExecution`, `Broadcaster`, `HistoryHelpers`, `LoopHandler` 4个子模块，但主文件仍有 ~20 个 `handle_info({:signal, ...})` 子句（428-673行，约245行）。

拆分方案：
```
lib/cortex/agents/llm_agent/
├── signal_handlers.ex    # 新增：所有 handle_info({:signal, ...}) 子句
├── tool_execution.ex     # 已有
├── broadcaster.ex        # 已有
├── history_helpers.ex    # 已有
└── loop_handler.ex       # 已有
```

具体步骤：
1. 创建 `LLMAgent.SignalHandlers` 模块
2. 将 `handle_info({:signal, ...})` 的所有子句（约245行）迁移过去
3. 在主模块中通过 `defdelegate` 或在 `handle_info` 中调用 `SignalHandlers.handle(signal, state)`
4. 主模块保留：Client API + init/terminate + handle_call/handle_cast + 非信号的 handle_info

预期效果：主文件从 955 行降至 ~700 行，信号处理逻辑集中管理。

#### 3.2 `agent_live_helpers.ex`（767行）→ 按职责域拆分

现状：混合了5类完全不同的职责，函数之间无强依赖。

拆分方案：
```
lib/cortex_web/live/helpers/
├── agent_live_helpers.ex          # 保留为聚合入口（import/alias 子模块）
├── agent_live_helpers/
│   ├── conversation.ex            # 会话管理：switch/reset/new/delete/archive（~200行）
│   ├── messaging.ex               # 消息发送+流式：send_message/accumulate_stream/create_and_stream（~150行）
│   ├── context.ex                 # 上下文处理：handle_context_selected/handle_folder_selected/emit_context_add（~120行）
│   └── signal_emitters.ex         # 信号发射：emit_permission_resolve/emit_conversation_switch/emit_model_change/emit_cancel（~80行）
```

具体步骤：
1. 按函数分组创建子模块
2. 主模块保留 `init_agent_state`, `resolve_model`, `list_available_models`, `base_messages` 等基础函数
3. 主模块 `import` 所有子模块，保持调用方零改动

预期效果：每个子模块 80-200 行，职责清晰。

#### 3.3 `jido_components.ex`（719行）→ 按UI区块拆分

现状：chat_panel(~230行), display_message系列(~150行), agents_panel(~45行), add_folder_modal(~40行), archived_conversations_modal(~100行), permission_modal(~120行) 混在一起。

拆分方案：
```
lib/cortex_web/live/components/
├── jido_components.ex             # 聚合入口，import 子模块
├── jido_components/
│   ├── chat_panel.ex              # chat_panel + 消息子组件（display_message/text_message/thinking_message 等）
│   ├── agents_panel.ex            # agents_panel
│   ├── modals.ex                  # add_folder_modal + archived_conversations_modal + permission_modal
```

具体步骤：
1. 将 chat_panel 及其关联的 display_message/text_message/thinking_message/tool_call_message/tool_result_message/notification_message/error_message 和辅助函数迁移到 `ChatPanel`
2. 将三个 modal 迁移到 `Modals`
3. agents_panel 较小，可独立或留在主模块
4. 主模块 `import` 子模块

预期效果：chat_panel.ex ~380行，modals.ex ~260行，主模块 ~80行。

#### 3.4 `memory/subconscious.ex`（617行）→ 抽离分析引擎

现状：GenServer 回调 + 信号路由 + 内容分析（含中文NLP）+ 提议创建，四类职责。

拆分方案：
```
lib/cortex/memory/
├── subconscious.ex                # GenServer + 信号路由（保留）
├── subconscious/
│   ├── analyzer.ex                # 内容分析：perform_analysis/extract_preferences/extract_facts/extract_patterns/extract_technologies + 中文处理（~250行）
│   ├── proposal_emitter.ex        # 提议创建+发射：create_and_emit_proposal/create_proposal/not_duplicate?（~60行）
```

具体步骤：
1. 将 `perform_analysis` 及其所有 `extract_*` 和中文处理函数迁移到 `Analyzer`
2. 将 `create_and_emit_proposal` 等迁移到 `ProposalEmitter`
3. 主模块保留 GenServer 回调和信号路由，调用子模块

预期效果：主文件从 617 行降至 ~300 行。

### 优先级 P1：去重 + 结构优化

#### 3.5 `settings_live/channels.ex` + `channels_component.ex`（516+514=1030行）→ 合并去重

现状：两个文件有大量重复代码——`save` 事件处理、`parse_int`、`parse_tab`、`get_config`、`get_enabled`、以及5个渠道表单组件（dingtalk_form/feishu_form/wecom_form/telegram_form/discord_form）几乎完全相同。

拆分方案：
```
lib/cortex_web/live/settings_live/
├── channels.ex                    # LiveView mount/handle_event，调用 ChannelsForms
├── channels_component.ex          # LiveComponent update/handle_event，调用 ChannelsForms
├── channels_forms.ex              # 新增：共享的表单组件 + 配置解析 + 保存逻辑
```

具体步骤：
1. 创建 `ChannelsForms` 模块，提取共享的：
   - 5个渠道表单组件（dingtalk_form/feishu_form/wecom_form/telegram_form/discord_form）
   - 共享辅助组件（toggle_enabled/input_group/select_group/save_button）
   - 配置解析函数（parse_int/parse_tab/get_config/get_enabled）
   - 保存逻辑（save 事件中的参数解析和持久化）
2. channels.ex 和 channels_component.ex 各自 `import ChannelsForms`
3. 两个文件各自只保留 mount/update 和路由层的 handle_event

预期效果：消除 ~400 行重复代码，channels.ex ~80行，channels_component.ex ~50行，channels_forms.ex ~400行。

#### 3.6 `tools/handlers/read_structure.ex`（428行）→ 按语言拆分解析器

现状：`extract_elixir_structure`、`extract_js_structure`、`extract_rust_structure`、`extract_python_structure`、`extract_go_structure` 各自独立，且新增语言支持时文件会持续膨胀。

拆分方案：
```
lib/cortex/tools/handlers/
├── read_structure.ex              # 入口：execute/do_execute/extract_structure（路由到子模块）
├── read_structure/
│   ├── elixir_parser.ex           # extract_elixir_structure + AST 处理 + format_* 辅助函数（~140行）
│   ├── js_parser.ex               # extract_js_structure（~30行）
│   ├── rust_parser.ex             # extract_rust_structure（~30行）
│   ├── python_parser.ex           # extract_python_structure（~40行）
│   ├── go_parser.ex               # extract_go_structure（~50行）
│   └── fallback_parser.ex         # extract_unsupported（~25行）
```

具体步骤：
1. 为每种语言创建 Parser 模块，统一接口 `parse(content) :: String.t()`
2. 主模块的 `extract_structure` 根据语言路由到对应 Parser
3. Elixir parser 最大（含 AST 处理和 format_section 等），其余较小

预期效果：主文件从 428 行降至 ~100 行，新增语言只需添加新 Parser 文件。

### 优先级 P2：小幅抽离（可选）

#### 3.7 `memory/knowledge_graph.ex`（736行）→ 仅抽离动态算法

报告建议拆成4个模块，但实际上 Node/Edge 结构和 CRUD 操作与图本身紧密耦合，不宜拆分。仅建议抽离计算密集的动态算法部分。

```
lib/cortex/memory/
├── knowledge_graph.ex             # 结构体 + CRUD + search + stats + 序列化
├── knowledge_graph/
│   └── dynamics.ex                # decay/reinforce/prune/spreading_activation（~180行）
```

#### 3.8 `memory/store.ex`（548行）→ 仅抽离文件持久化

```
lib/cortex/memory/
├── store.ex                       # GenServer + 业务逻辑
├── store/
│   └── persistence.ex             # load_from_file/flush_to_disk/MEMORY.md 解析（~80行）
```

#### 3.9 `jido_live.ex`（434行）→ 仅抽离 mount 初始化

mount 函数 + init_workspace_conversation + ensure_current_conversation 约 90 行，可抽离到 `JidoLive.Setup`。但收益较小，可延期。

---

## 四、实施顺序建议

```
Phase 1（高收益，低风险）:
  1. channels.ex + channels_component.ex 去重  → 消除 ~400 行重复
  2. jido_components.ex 按UI区块拆分           → 模板维护性大幅提升

Phase 2（核心模块，需谨慎）:
  3. llm_agent.ex 抽离信号处理                 → 需确保信号路由不中断
  4. agent_live_helpers.ex 按职责域拆分         → 需确保 LiveView 功能不受影响

Phase 3（领域模块）:
  5. subconscious.ex 抽离分析引擎              → 相对独立，风险低
  6. read_structure.ex 按语言拆分解析器         → 纯函数，最安全

Phase 4（可选优化）:
  7. knowledge_graph.ex 抽离 dynamics
  8. store.ex 抽离 persistence
  9. jido_live.ex 抽离 mount
```

每个 Phase 完成后运行 `mix test` 确保无回归。

---

## 五、BDD 驱动迭代流程说明

本计划的实施应遵循项目标准的 BDD 驱动任务迭代流程（参见 `.agent/skills/bddc/SKILL.md`）：

1. 每个 Phase 开始前，先定义 BDD 场景（验收标准）
2. 使用 `bddc` 工具生成对应的测试骨架
3. 实现拆分重构，确保所有 BDD 场景通过
4. 每个 Phase 完成后通过 `mix test` 全量回归

关键验收标准示例：
- 拆分后所有现有测试必须零修改通过
- 拆分后的模块 public API 与原模块完全一致（调用方零改动）
- 无循环依赖引入
