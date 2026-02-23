# 评审报告：网页端记忆查看编辑工具规划文档

**评审日期**: 2026-02-23  
**评审对象**: `docs/plans/20260223_memory_ui_planning.md`  
**评审人**: Code Review Agent

---

## 一、总体评价

规划文档结构完整，覆盖了从现状分析、架构决策、BDD 场景、后端 API、前端实现到性能优化的全链路。参考架构对比（Hmem/Nanobot）体现了调研深度。整体可执行性较高，但存在若干与现有代码不一致的问题和设计盲点，需在实施前修正。

**评级**: B+（良好，需修正后可执行）

---

## 二、与现有代码的一致性校验

### 2.1 API 引用准确性

| 规划文档引用 | 实际代码 | 状态 |
|---|---|---|
| `WorkingMemory.list_all/0` | `WorkingMemory.list_all/0` 存在 | OK |
| `WorkingMemory.remove/1` | `WorkingMemory.remove/1` 存在 | OK |
| `WorkingMemory.clear/0` | `WorkingMemory.clear/0` 存在 | OK |
| `Proposal.list_pending/0` | 实际签名为 `Proposal.list_pending/1`（接受 opts keyword list） | **需修正** |
| `Proposal.reject/1` | `Proposal.reject/1` 存在 | OK |
| `Store.accept_proposal/1` | 实际签名为 `Store.accept_proposal/2`（第二参数 server，默认 `__MODULE__`） | **需修正** |
| `Cortex.Memory.load_memory/2` | `Cortex.Memory.load_memory/2` 存在 | OK |
| `Cortex.Memory.update_memory/3` | 实际签名为 `Cortex.Memory.update_memory/4`（含 workspace_id 默认参数） | **需修正** |

### 2.2 信号类型校验

| 规划文档引用 | SignalTypes 模块 | 状态 |
|---|---|---|
| `memory.working.saved` | `memory_working_saved/0` 存在 | OK |
| `memory.observation.created` | `memory_observation_created/0` 存在 | OK |
| `memory.proposal.created` | `memory_proposal_created/0` 存在 | OK |
| `memory.observation.deleted` | **不存在** | **需新增** |
| `memory.observation.updated` | **不存在** | **需新增** |

规划文档第六节已提到需要在 `SignalTypes` 中新增这两个信号类型，这一点是正确的。但文档中将文件路径写为 `lib/cortex/memory/signal_types.ex`，实际路径一致，确认无误。

### 2.3 路由结构校验

规划文档中的路由示例：
```elixir
pipe_through [:browser, :require_admin]
```

实际 router.ex 使用的是编译期条件判断：
```elixir
if Application.compile_env(:cortex, :require_admin, true) do
  pipe_through [:browser, :require_admin]
else
  pipe_through :browser
end
```

规划文档简化了这一逻辑，实施时需注意保持现有的条件分支结构，将 `live "/memory"` 路由添加到 `live_session :admin` 块内即可。

### 2.4 Layout 结构校验

规划文档中的 Layout 修改示例基本准确，但现有 `app.html.heex` 中：
- 使用 `@active_tab` 来高亮当前导航项
- Settings 链接使用 `navigate="/settings/channels"` 而非 `/settings`

规划文档的示例与现有风格一致，可直接使用。但需注意：现有 Layout 中 Memory 按钮应插入在 Settings 按钮**之前**，规划文档已正确体现这一点。

---

## 三、架构设计评审

### 3.1 正面评价

1. **"不使用 Phoenix Generator" 的决策正确**：Memory 页面确实不涉及数据库 CRUD，纯 LiveView 实现更轻量。
2. **"暂不改为按日期分文件存储" 的决策合理**：避免了存储层重构的风险，UI 层分组展示是更低成本的方案。
3. **Tab 结构设计合理**：4 个 Tab 覆盖了记忆系统的主要可视化需求，优先级排序（P0-P3）务实。
4. **信号订阅机制**：`handle_info({:signal, ...})` 的模式与 AGENTS.md 中规定的标准投递形态一致。

### 3.2 问题与风险

#### 问题 1：`load_observations_by_date/1` 的实现位置不当

规划文档将 `load_observations_by_date/1` 放在 `Memory.Store` GenServer 中。但该函数本质上是对已有 `load_observations/1` 返回结果的**分组变换**，不需要 GenServer 调用。

**建议**：将按日期分组逻辑放在 LiveView 层或独立的 Helper 模块中，避免给 GenServer 增加不必要的调用负担。

```elixir
# 建议：在 LiveView 中直接分组
defp group_by_date(observations) do
  observations
  |> Enum.group_by(fn obs -> DateTime.to_date(obs.timestamp) end)
  |> Enum.sort_by(fn {date, _} -> date end, {:desc, Date})
end
```

#### 问题 2：防级联保护未在 LiveView 信号回调中体现

AGENTS.md 明确要求"信号回调中禁止触发可能产生新信号的链式反应"。规划文档的 `handle_info` 回调中调用了 `reload_working_memory(socket)` 等函数，但未说明这些函数是否会触发新的信号发射。

**建议**：在实施时明确标注 reload 函数为纯读操作，不发射信号。建议在 BDD 场景中增加一个防级联测试场景。

#### 问题 3：Proposal Tab 的 Accept 操作信号链未完整描述

`Store.accept_proposal/1` 内部会发射 3 个信号（`memory.proposal.accepted`、`memory.kg.node_added`、`memory.observation.created`）。LiveView 如果同时订阅了 `memory.observation.created` 和 `memory.proposal.created`，Accept 操作会触发多次 UI 刷新。

**建议**：
- 使用防抖（debounce）机制合并短时间内的多次刷新
- 或者在 Accept 操作后主动刷新一次，忽略后续信号触发的刷新

#### 问题 4：`Cortex.Memory.update_memory/3` 签名不匹配

规划文档 Tab 4 中写的是 `Cortex.Memory.update_memory/3`，但实际函数签名为：
```elixir
def update_memory(workspace_root, level, content, workspace_id \\ nil)
```
这是一个 4 参数函数（含默认值）。LiveView 调用时需要传入 `workspace_root`，这意味着 LiveView 需要知道当前工作区根路径。

**建议**：在 `mount/3` 中从配置或 Session 中获取 `workspace_root` 并存入 socket assigns。

#### 问题 5：ETS 表的进程安全性

`Proposal` 模块使用 ETS 表（`:public`），LiveView 进程直接调用 `Proposal.list_pending/1` 是安全的。但 `Proposal.accept/1` 和 `Proposal.reject/1` 也是直接 ETS 操作，没有经过 GenServer 序列化。

这在当前单用户场景下问题不大，但如果未来多用户同时操作 Proposal Tab，可能出现竞态条件（如两个用户同时 Accept 同一个 Proposal）。

**建议**：在 V2 迭代中考虑将 Proposal 操作包装到 GenServer 中，或在 UI 层增加乐观锁。

---

## 四、BDD 场景评审

### 4.1 场景覆盖度

| 核心功能 | BDD 场景 | 覆盖 |
|---|---|---|
| 查看工作记忆 | 场景 1 | OK |
| 删除观察项 | 场景 2 | OK |
| 按日期分组 | 场景 3 | OK |
| 编辑 MEMORY.md | 场景 4 | OK |
| 实时信号更新 | 场景 5 | OK |
| 提议队列操作 | **缺失** | **需补充** |
| 清空工作记忆 | **缺失** | **需补充** |
| 编辑观察项内容 | **缺失** | **需补充** |

### 4.2 BDD 指令集缺口

规划文档第十节列出了需要的 BDD 指令：`visit_page`、`assert_element_exists`、`click_button`、`assert_signal_emitted`、`assert_count`。

经核查 `priv/bdd/instructions_v1.exs`，现有指令集中：
- `assert_signal_emitted` — 已存在
- `visit_page` — **不存在**
- `assert_element_exists` — **不存在**
- `click_button` — **不存在**
- `assert_count` — **不存在**

这意味着 LiveView UI 测试所需的指令集**大部分缺失**。这是一个实施阻塞项，需要在 BDD DSL 编写之前先扩展指令集。

**建议**：将"扩展 BDD 指令集"提升为 P0 任务，排在 BDD DSL 场景编写之前。或者考虑 BDD 场景仅覆盖后端逻辑（信号发射、数据变更），UI 交互测试使用标准 LiveView 测试（`Phoenix.LiveViewTest`）。

### 4.3 BDD 场景语法问题

规划文档中的 BDD DSL 语法使用了 `FEATURE` / `SCENARIO` / `GIVEN` / `WHEN` / `THEN` / `AND` 关键字，但未展示完整的 DSL 文件结构（如文件头、指令引用等）。实施时需确认与 BDDC 编译器的实际语法规范一致。

---

## 五、任务 DAG 评审

### 5.1 依赖关系问题

当前 DAG：
```
memory_ui_planning
  ├─ write_bdd_dsl
  ├─ implement_backend_api
  ├─ implement_liveview
  └─ verify_bdd
```

问题：
1. `write_bdd_dsl` 和 `implement_backend_api` 被标记为并行，但 BDD DSL 需要引用后端 API 的信号类型（如 `memory.observation.deleted`），而这些信号类型需要先在 `SignalTypes` 中定义。
2. `implement_liveview` 依赖 `implement_backend_api`（需要 `delete_observation`、`update_observation` 等新 API），但 DAG 中未体现这一依赖。
3. 缺少"扩展 BDD 指令集"节点。

**建议修正后的 DAG**：
```
memory_ui_planning
  ├─ extend_signal_types          (新增 deleted/updated 信号)
  ├─ extend_bdd_instructions      (新增 LiveView 测试指令)
  ├─ write_bdd_dsl                (依赖: extend_bdd_instructions)
  ├─ implement_backend_api        (依赖: extend_signal_types)
  │   ├─ add_store_delete_observation
  │   ├─ add_store_update_observation
  │   └─ add_store_load_by_date   (建议移至 LiveView 层)
  ├─ implement_liveview           (依赖: implement_backend_api)
  │   ├─ create_memory_live_index
  │   ├─ update_router
  │   └─ update_app_layout
  └─ verify_bdd                   (依赖: write_bdd_dsl + implement_liveview)
```

---

## 六、性能与安全评审

### 6.1 性能

- 虚拟滚动策略（Phoenix LiveView Streams）合理，但建议在 P0 阶段就使用 Streams，而非等到 P3。Streams 是 LiveView 的标准列表渲染方式，不增加复杂度。
- 30 秒定时刷新（`Memory.Store` 的 `schedule_flush`）与 LiveView 的实时信号更新可能产生时序不一致：用户编辑后信号已触发 UI 刷新，但磁盘数据尚未持久化。建议在写操作后立即调用 `flush/0`。

### 6.2 安全

- 路由使用了 `require_admin` pipeline，符合安全要求。
- `Cortex.Memory.update_memory/4` 直接写文件，但 `Cortex.Memory` 模块未使用 `Security.validate_path` 进行沙箱校验（与 `Memory.Store` 不同）。Tab 4 的 MEMORY.md 编辑功能需要确保路径安全。

**建议**：在 `Cortex.Memory.update_memory/4` 中增加路径校验，或在 LiveView 层限制 level 参数只能为 `:global` 或 `:workspace`。

---

## 七、文档质量评审

### 7.1 优点
- 结构清晰，章节编号完整
- 参考架构对比有深度
- "不实施的内容"章节明确了边界
- 风险与依赖分析到位

### 7.2 改进建议
- 第六节"后端 API 扩展"中的函数签名应与实际代码保持一致（如 server 参数）
- 第七节 LiveView 实现中缺少错误处理描述（如 GenServer 不可用时的降级策略）
- 附录中的外部链接（Hmem GitHub、Nanobot Medium）应确认可访问性

---

## 八、总结与建议

### 实施前必须修正的问题（Blockers）

1. 修正 API 签名引用（`Proposal.list_pending/1`、`Store.accept_proposal/2`、`Cortex.Memory.update_memory/4`）
2. 确认 BDD 指令集扩展方案（扩展指令集 vs 使用 LiveViewTest）
3. 修正任务 DAG 依赖关系

### 实施前建议修正的问题（Improvements）

4. 将 `load_observations_by_date` 逻辑移至 LiveView 层
5. 增加防级联保护的 BDD 测试场景
6. 增加 Proposal Tab 操作的 BDD 场景
7. 在 `Cortex.Memory.update_memory` 中增加路径安全校验
8. P0 阶段即使用 LiveView Streams 渲染列表

### 可延后处理的问题（Deferred）

9. Proposal ETS 竞态条件（V2）
10. 多次信号触发的 UI 防抖（可在实施中根据实际体验决定）
