# 向后兼容与逻辑冲突分析

日期：2026-02-18
范围：`/home/Debian13/code/cortex`（主要聚焦 `lib/` 代码路径，补充少量测试/BDD 逻辑）

## 1. 向后兼容代码清单（按主题归类）

### 1.1 信号与事件兼容
- `lib/cortex/signal_catalog.ex`
  保留旧事件名清单：`deprecated_events/0`（如 `agent.turn.complete`, `tool.result.output` 等），用于历史数据兼容标记。
- `lib/cortex/history/signal_recorder.ex`
  在 JSONL 中标记 `deprecated` 字段，依据 `SignalCatalog.deprecated_events/0`。
- `lib/cortex/signal_bridge.ex`
  作为“过渡组件”将 SignalHub 信号转发到 PubSub，让旧 LiveView 订阅者仍能收到信号。
- `lib/cortex/events/session_event_bridge.ex`
  同时发射 SignalHub 事件并通过 PubSub 广播给 legacy 订阅者。

### 1.2 Tape/历史记录兼容
- `lib/cortex/agents/llm_agent.ex`
  `tape_entry_to_message/1` 与 `tape_entry_to_full_history/1` 仍识别旧事件类型（如 `tool.result.output`, `agent.tool_calls.detected`），兼容旧格式的 Tape/历史信号。
- `lib/cortex/bdd/instructions/v1.ex`
  ✅ 已移除 `history.jsonl` fallback（2026-02-18）；BDD 仅允许 Tape 作为来源。

### 1.3 Hook 回调兼容
- `lib/cortex/agents/hook.ex`
  使用 `@optional_callbacks` 允许旧 Hook 实现缺少新回调而不报错。
- `lib/cortex/agents/llm_agent.ex`
  `HookRunner.run/4` 返回值兼容“裸输出”（非 map 输出）以支持旧 Hook 行为。

### 1.4 LLM 模型与格式兼容
- `lib/cortex/llm/llmdb.ex`
  支持 OpenAI/OpenRouter 格式的 `/models` 响应，并在失败时回退到本地 `llm_db`。
- `lib/cortex/config/llm_resolver.ex`
  当数据库中不存在模型时，fallback 到默认模型与环境变量配置。

### 1.5 工具与解析兼容
- `lib/cortex/tools/handlers/read_structure.ex`
  对结构提取使用 Regex fallback（`extract_elixir_fallback/1`）。
- `lib/cortex/runners/cli.ex`
  CLI 走“通用 fallback：直接传 prompt”路径。

### 1.6 备份/旧实现遗留文件（非运行时兼容，但易混淆）
- `lib/cortex/clients/*.ex.bak`, `lib/cortex/agents/compaction.ex.bak`
  这些 `.bak` 文件保留了旧逻辑与 fallback 方案，不参与运行但会影响维护者理解。

## 2. 逻辑相互冲突或不一致点

### 2.1 “双向桥接”描述与实际行为不一致
- `lib/cortex/signal_bridge.ex`
  模块文档声明“PubSub ↔ SignalHub 双向桥接”，但 `init/1` 仅订阅 SignalHub 并转发到 PubSub，没有从 PubSub 订阅并转发回 SignalHub 的实现。
  结果：对“旧 PubSub 事件 → 新 SignalHub”的路径是缺失的。

### 2.2 标准信号投递格式与实际兼容路径并存
- 标准约定为 `{:signal, %Jido.Signal{...}}`。
- `lib/cortex/history/signal_recorder.ex` 同时处理 `{:signal, signal}` 和 `%Jido.Signal{}` 两种形式。
  结果：实现层仍保留非标准投递方式，导致新旧路径并存，容易造成维护者对统一格式的误解。

### 2.3 ReqLLM 工具结果 API 的新旧签名混用
- `lib/cortex/history/tape_context.ex` 使用 `ReqLLM.Context.tool_result(call_id, tool_name, output)`（3 参数）。
- `lib/cortex/agents/llm_agent.ex` 中多个路径使用 `ReqLLM.Context.tool_result(call_id, result)`（2 参数）。
  结果：若 ReqLLM 仅支持 3 参数，则旧历史/兼容路径会在运行时报错；如果同时支持 2 参数，则系统存在“新旧格式混用”，可能造成输出字段不一致。

### 2.4 Tape 作为唯一真相源与历史文件 fallback 的冲突
- ✅ 已修复：BDD 测试不再使用 `history.jsonl` fallback，只以 Tape 为唯一来源。

### 2.5 LLM 历史恢复路径存在“新旧并行但仅用其一”的实现偏差
- `lib/cortex/agents/llm_agent.ex` 已在 `init/1` 中使用 `TapeContext.to_llm_messages/2`。
- 同时保留 `restore_messages_from_tape/1` 与 `tape_entry_to_message/1`（基于旧事件类型的解析），但目前无调用点。
  结果：兼容代码可能已失效但仍保留，容易误导维护者或导致未来重复实现。

## 3. 风险与影响评估（简要）

- 兼容代码长期保留会扩大测试矩阵与维护成本，尤其是“信号投递格式”和“工具结果签名”两类核心路径。
- SignalBridge 描述与实现不一致，容易让迁移过程出现“以为已经双向桥接”的假象。
- Tape/历史文件双路径会削弱“唯一真相源”的设计目标，且测试可能掩盖真实数据问题。

## 4. 建议（不含实现，仅用于后续决策）

1. 明确“仍需兼容”的范围与截止日期，把兼容点写入 `SignalCatalog.deprecated_events/0` 或独立清单。
2. 统一 ReqLLM `tool_result` 的调用签名，明确是否支持 2 参数；若不支持，立即清理或加适配层。
3. SignalBridge 文档与实现保持一致：要么补齐 PubSub → SignalHub 逻辑，要么更新文档说明“单向”。
4. 已完成：BDD 测试移除 `history.jsonl` fallback，Tape 作为唯一真相源。
