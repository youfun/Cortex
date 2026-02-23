# Bub Tape 与 Cortex History 对比分析

> 深度源码对比，识别 Bub Tape 系统中值得借鉴的规范化设计。

---

## 1. 架构全景对比

```
┌─────────────── Bub ───────────────┐    ┌──────────── Cortex ────────────┐
│                                   │    │                                     │
│  TapeEntry (Republic SDK)         │    │  3 个独立子系统，各自为政：             │
│  ┌─────────────────────┐          │    │                                     │
│  │ id: int (单调递增)    │          │    │  1) LLMAgent.full_history (内存 list) │
│  │ kind: str            │          │    │     → 无固定 schema，字段随意          │
│  │ payload: dict        │          │    │                                     │
│  │ meta: dict           │          │    │  2) Tape.Store (GenServer + JSONL)   │
│  └────────┬────────────┘          │    │     → Entry{id,type,data,timestamp,  │
│           │                       │    │       trace_id,source}               │
│  TapeService (高层 API)            │    │                                     │
│  ├─ append_event(name, data)      │    │  3) SignalRecorder (history.jsonl)   │
│  ├─ handoff(name, state)          │    │     → 信号原始 dump，CloudEvents 格式  │
│  ├─ search(query, fuzzy)          │    │                                     │
│  ├─ anchors() / fork / merge      │    │  彼此不关联，无统一查询 API              │
│  └─ info() → TapeInfo             │    │                                     │
│                                   │    │                                     │
│  FileTapeStore (持久化)            │    │  DualTrackFilter (分流器)             │
│  ├─ append-only JSONL             │    │  ├─ llm_visible? (前缀白名单)         │
│  ├─ fork / merge (带 ID 续编)      │    │  └─ signal_to_llm_message (手动映射)  │
│  └─ archive (时间戳备份)            │    │                                     │
│                                   │    │                                     │
│  TapeContext (LLM 视图选择器)      │    │  无等价物 — LLM context 在              │
│  └─ _select_messages()            │    │  LLMAgent 内硬编码拼装                  │
│     按 kind 精确重建对话流           │    │                                     │
└───────────────────────────────────┘    └─────────────────────────────────────┘
```

---

## 2. 逐项对比

### 2.1 条目结构 (Entry Schema)

| 维度 | Bub `TapeEntry` | Jido `Tape.Entry` | 差距 |
|---|---|---|---|
| **ID 策略** | `int`，单调递增，持久化时自动分配 | 信号 UUID (string)，无序 | Bub 可按 ID 范围查询，Jido 只能按时间排序 |
| **分类字段** | `kind`（6 种：`message`, `tool_call`, `tool_result`, `command`, `event`, `anchor`） | `type`（信号类型字符串，如 `"agent.chat.request"`） | Bub 是**语义分类**，Jido 是**信号路由地址** |
| **载荷** | `payload`（纯数据，结构按 kind 约定） | `data`（信号 data 字段原样存储） | 等价 |
| **元数据** | `meta`（独立 dict） | 无专门 meta 字段，trace_id/source 是顶层字段 | Bub 更灵活 |
| **因果追踪** | 通过 `id` 递增顺序天然建立因果链 | `trace_id`（可选，经常为 nil） | Bub 隐式因果 > Jido 显式但不可靠 |

**Bub 源码**（`store.py:100-106`）：
```python
@staticmethod
def entry_to_payload(entry: TapeEntry) -> dict[str, object]:
    return {
        "id": entry.id,        # 单调递增 int
        "kind": entry.kind,    # 语义分类
        "payload": dict(entry.payload),
        "meta": dict(entry.meta),
    }
```

**Jido 源码**（`persistence.ex:130-138`）：
```elixir
defp entry_to_map(%Entry{} = entry) do
  %{
    id: entry.id,            # 信号 UUID，无序
    type: entry.type,        # 信号路由地址
    data: entry.data,
    timestamp: format_timestamp(entry.timestamp),
    trace_id: entry.trace_id,  # 可选
    source: entry.source
  }
end
```

### 2.2 条目类型 (Kind System)

Bub 严格定义了 6 种 kind，每种 kind 的 payload 结构是**约定固定的**：

| Kind | Payload 结构 | 生产者 | 用途 |
|---|---|---|---|
| `message` | `{role, content}` | AgentLoop / Router | 用户和 LLM 的对话轮次 |
| `tool_call` | `{calls: [{id, type, function: {name, arguments}}]}` | Republic SDK (LLM) | LLM 请求调用工具 |
| `tool_result` | `{results: [str \| dict]}` | Republic SDK (Tools) | 工具执行返回 |
| `command` | `{origin, kind, raw, name, status, elapsed_ms, output}` | Router._record_command | 命令执行（用户/AI） |
| `event` | `{step, model, ...}` 等自定义 | ModelRunner / AgentLoop | 循环状态事件 |
| `anchor` | `{name, state}` | TapeService.handoff | 检查点 / 阶段标记 |

**关键洞察**：`command` 类型是 Bub 独有的，它统一了「工具调用结果」和「命令执行记录」，并且**始终包含**：
- `origin`: `"human"` 还是 `"assistant"`
- `status`: `"ok"` 还是 `"error"`
- `elapsed_ms`: 执行耗时
- `name`: 命令/工具名
- `output`: 输出内容

**Bub 源码**（`router.py:332-352`）：
```python
def _record_command(self, *, command, status, output, elapsed_ms, origin):
    self._tape.append_event(
        "command",
        {
            "origin": origin,        # human / assistant
            "kind": command.kind,    # internal / shell
            "raw": command.raw,      # 原始命令文本
            "name": command.name,    # 命令名
            "status": status,        # ok / error
            "elapsed_ms": elapsed_ms,
            "output": output,
        },
    )
```

**Jido 现状**：工具执行结果分散在 3 个地方，格式各不相同：

```elixir
# 1) LLMAgent.full_history — 手工拼装
%{type: "tool_result", timestamp: ..., tool_call_id: call_id,
  tool_name: tool_name, data: output}
# ❌ 无 status, 无 elapsed_ms, 无 origin

# 2) Tape.Store — 从信号直接转换
%Entry{type: "tool.result.read", data: signal.data, ...}
# ❌ data 结构取决于每个工具的信号 payload，不统一

# 3) SignalRecorder — 信号原始 dump
%{type: "tool.result.read", data: %{...}, source: "/tool/read_file", ...}
# ❌ CloudEvents 格式，但 data 内部结构不规范
```

### 2.3 Anchor 机制（检查点）

Bub 的 Anchor 是 Tape 的核心特性之一：

```python
# 创建检查点
tape.handoff("phase-1-complete", state={"files_modified": 3})

# 查询两个 anchor 之间的条目
entries = tape.between_anchors("phase-1", "phase-2", kinds=("command",))

# 获取最后一个 anchor 之后的所有条目
entries = tape.from_last_anchor(kinds=("message", "command"))

# 列出所有 anchor
anchors = tape.anchors(limit=10)
# → [AnchorSummary(name="session/start", state={"owner": "human"}),
#    AnchorSummary(name="phase-1-complete", state={"files_modified": 3})]
```

**用途**：
- 上下文窗口管理：只加载最近 anchor 之后的内容
- 任务阶段标记：handoff 时总结当前状态
- 分支/合并：fork 从当前 anchor 创建分支

**Jido 现状**：`session.branch.*` 信号存在，但无 anchor 概念。分支只是文件复制，无语义检查点。

### 2.4 TapeContext — LLM 视图选择器

这是 Bub 最精妙的设计。`context.py` 的 `_select_messages` 函数从 Tape 条目中**精确重建 OpenAI 消息格式**：

```python
def _select_messages(entries, _context):
    messages = []
    pending_calls = []

    for entry in entries:
        if entry.kind == "message":
            # → {"role": "user/assistant", "content": "..."}
            messages.append(dict(entry.payload))

        elif entry.kind == "tool_call":
            # → {"role": "assistant", "content": "", "tool_calls": [...]}
            pending_calls = _append_tool_call_entry(messages, entry)

        elif entry.kind == "tool_result":
            # → {"role": "tool", "tool_call_id": "...", "content": "..."}
            _append_tool_result_entry(messages, pending_calls, entry)
            pending_calls = []

    return messages
```

**关键价值**：
- **Single Source of Truth**：Tape 是唯一数据源，LLM 消息列表是派生视图
- **确定性重建**：任何时候从 Tape 重建的消息列表完全一致
- **可选过滤**：可以只选 anchor 后的条目，自动裁剪上下文

**Jido 现状**：LLM context 在 `LLMAgent` 中作为独立状态维护（`state.llm_context`），与 full_history 和 Tape 是**三份独立数据**。恢复时 `restore_full_history_from_tape` 有大量手工映射代码且 tool_name 经常丢失（`"unknown"`）。

### 2.5 Fork / Merge

```python
# store.py — fork 时复制当前 tape 并记录分叉点
def fork(self, source: str) -> str:
    fork_suffix = uuid.uuid4().hex[:8]
    new_name = f"{source}__{fork_suffix}"
    source_file = self._tape_file(source)
    target_file = self._tape_file(new_name)
    source_file.copy_to(target_file)  # 复制 + 记录 fork_start_id
    return new_name

# merge 时只合并分叉点之后的新条目
def merge(self, source: str, target: str) -> None:
    source_file = self._tape_file(source)
    target_file = self._tape_file(target)
    target_file.copy_from(source_file)  # 只追加 fork_start_id 之后的条目
    source_file.path.unlink(missing_ok=True)
```

**关键**：`fork_start_id` 确保 merge 时不会重复条目。Jido 的 `branch_session` 只是简单的文件复制，无合并能力。

### 2.6 搜索能力

Bub 提供了内置的**模糊搜索**（`rapidfuzz`）：

```python
def search(self, query, *, limit=20, all_tapes=False):
    for entry in reversed(tape.read_entries()):
        payload_text = json.dumps(entry.payload)
        if normalized_query in payload_text.lower():
            results.append(entry)
        elif self._is_fuzzy_match(normalized_query, payload_text, meta_text):
            results.append(entry)
```

Jido 的 `Tape.Aggregator` 只有 `find_causal_chain/2`（按 trace_id 过滤），无全文搜索。

---

## 3. 核心差距总结

| 能力 | Bub Tape | Jido History | 差距评级 |
|---|---|---|---|
| **统一条目结构** | ✅ `TapeEntry{id, kind, payload, meta}` | ❌ 3 套独立结构 | 🔴 严重 |
| **语义分类 (kind)** | ✅ 6 种固定 kind | ❌ 用信号 type 字符串替代 | 🟡 中等 |
| **工具结果规范化** | ✅ `command` kind 统一 status/elapsed_ms/origin | ❌ 字段随意、经常缺失 | 🔴 严重 |
| **单调递增 ID** | ✅ int，支持范围查询 | ❌ UUID，无序 | 🟡 中等 |
| **Anchor 检查点** | ✅ handoff + between_anchors 查询 | ❌ 无 | 🔴 严重 |
| **LLM 视图选择器** | ✅ TapeContext._select_messages | ❌ 手工维护 llm_context | 🟡 中等 |
| **Fork / Merge** | ✅ 带 fork_start_id 的精确合并 | 🟠 文件复制，无合并 | 🟡 中等 |
| **全文搜索** | ✅ 精确 + 模糊 | ❌ 仅 trace_id 过滤 | 🟡 中等 |
| **Single Source of Truth** | ✅ Tape 是唯一真相源 | ❌ 3 份数据各自为政 | 🔴 严重 |

---

## 4. 借鉴建议（按优先级排序）

### P0: 统一条目结构 + 工具结果规范化

**目标**：让 Tape 成为唯一真相源，消除 `full_history` 和 `SignalRecorder` 的重复。

**核心改动**：引入 `kind` 分类系统到 `Tape.Entry`：

```elixir
defmodule Cortex.History.Tape.Entry do
  @type kind :: :message | :tool_call | :tool_result | :command | :event | :anchor
  
  defstruct [
    :id,          # integer, 单调递增
    :kind,        # atom, 语义分类
    :payload,     # map, 按 kind 约定结构
    :meta,        # map, 元数据 (trace_id, source, session_id)
    :timestamp    # DateTime
  ]
end
```

**工具结果 payload 规范**（对齐 Bub `command` kind）：

```elixir
# kind == :tool_result
%{
  tool_name: "edit_file",
  call_id: "call_abc123",
  origin: "assistant",       # ← 新增：谁触发的
  status: "error",           # ← 新增：ok / error
  elapsed_ms: 45,            # ← 新增：执行耗时
  output: "old_string not found in lib/foo.ex..."
}
```

### P1: Anchor 检查点

**目标**：支持上下文窗口裁剪和任务阶段标记。

```elixir
# kind == :anchor
%{name: "phase-1-complete", state: %{files_modified: 3}}

# API
Tape.Store.handoff(session_id, "task-done", state: %{summary: "..."})
Tape.Store.from_last_anchor(session_id, kinds: [:message, :tool_result])
```

### P2: TapeContext — 从 Tape 派生 LLM 消息

**目标**：消除 `state.llm_context` 的独立维护，改为从 Tape 实时投影。

```elixir
defmodule Cortex.History.TapeContext do
  def to_llm_messages(entries) do
    entries
    |> Enum.flat_map(&entry_to_messages/1)
  end

  defp entry_to_messages(%{kind: :message, payload: payload}),
    do: [payload]
  defp entry_to_messages(%{kind: :tool_call, payload: %{calls: calls}}),
    do: [%{role: "assistant", content: "", tool_calls: calls}]
  defp entry_to_messages(%{kind: :tool_result, payload: p}),
    do: [%{role: "tool", tool_call_id: p.call_id, content: p.output}]
  defp entry_to_messages(_), do: []
end
```

### P3: 单调递增 ID + 搜索

改为 `integer` ID，支持范围查询和 anchor 间切片。搜索可后续加入（ETS / 简单全文匹配）。

---

## 5. 实施影响评估

| 改动 | 影响范围 | 风险 | 工作量 |
|---|---|---|---|
| P0: 统一 Entry | `Tape.Entry`, `Tape.Store`, `Tape.Persistence`, `LLMAgent` | 中 — 需迁移现有 JSONL 文件 | 3-5 天 |
| P1: Anchor | `Tape.Store`, `Tape.Service`(新), `LLMAgent` | 低 — 纯新增 | 2 天 |
| P2: TapeContext | `TapeContext`(新), `LLMAgent`(删除 llm_context) | 高 — 核心流程重构 | 3-5 天 |
| P3: 递增 ID + 搜索 | `Tape.Store`, `Tape.Persistence` | 低 — 内部改动 | 1-2 天 |

**建议实施顺序**：P0 → P3 → P1 → P2（渐进式，每步可独立验证）
