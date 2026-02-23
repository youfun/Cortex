# 网页端记忆查看编辑工具 - BDD 驱动实施规划

**日期**: 2026-02-23  
**任务**: 为 Cortex 记忆系统增加网页端查看/编辑界面  
**方法**: BDD 驱动开发 + LiveView

### 修订记录

| 版本 | 日期 | 变更内容 |
|------|------|----------|
| v1.0 | 2026-02-23 | 初始规划 |
| v1.1 | 2026-02-23 | 根据代码评审修正：修正 API 签名（`Proposal.list_pending/1`、`Store.accept_proposal/2`、`Memory.update_memory/4`）；修正任务 DAG 依赖关系；将 `load_observations_by_date` 移至 LiveView 层；补充 BDD 场景（清空工作记忆、提议操作、编辑观察项、防级联保护）；采用双轨测试策略解决 BDD 指令集缺口；增加信号防抖机制；增加路径安全校验说明；P0 即采用 LiveView Streams |

---

## 一、现有记忆系统分层分析

| 层级 | 模块 | 存储形式 | 特点 |
|------|------|----------|------|
| 工作记忆 (Working) | `WorkingMemory` GenServer | 纯内存 | focus/curiosities/concerns/goals，7±2 容量限制 |
| 预意识 (Preconscious) | `Preconscious` GenServer | 内存 | 从 KG 中浮现相关记忆 |
| 观察存储 (Store) | `Memory.Store` GenServer | MEMORY.md 文件 | 持久化观察项，按优先级分级 |
| 知识图谱 (KG) | `KnowledgeGraph` | 内存结构体 | 节点/边/扩散激活 |
| 提议队列 (Proposals) | `Proposal` ETS | ETS 表 | pending/accepted/rejected/deferred |
| 全局/工作区记忆 | `Cortex.Memory` | MEMORY.md 文件 | global + workspace 两级 |

---

## 二、参考架构对比

### Hmem（分层懒加载）
- **5 层深度**：Level 1 摘要（20 tokens）→ 按需加载更深层
- **单 SQLite 文件**：跨工具/设备可移植
- **优势**：避免一次性注入 3000-8000 tokens

### Nanobot（本地历史图）
- **Stateful memory**：维护用户历史图
- **跨会话记忆**：记住用户兴趣

### 按日期分文件模式（多篇文章推荐）
- **优势**：只加载最近 N 天，旧记忆可归档，写入只更新当天文件
- **劣势**：全局搜索/去重复杂化

**决策**：暂不改为按日期分文件存储，保持当前单文件架构，UI 层做分组展示即可。

---

## 三、架构决策

### 生成器选择
- **不使用 Phoenix Generator**：Memory 页面是纯展示/编辑界面，不涉及数据库 CRUD
- **不使用 BCC**：无跨系统集成需求，直接编写 LiveView
- **使用 BDD DSL**：定义核心交互行为，确保可测试性

### 技术栈
- **前端**：Phoenix LiveView + TailwindCSS
- **后端**：扩展 `Memory.Store` GenServer API
- **实时通信**：订阅 SignalHub 信号
- **测试**：BDDC 编译 DSL 生成 ExUnit 测试

---

## 四、任务 DAG（Taskctl）

```
memory_ui_planning
  ├─ extend_signal_types              # 新增 deleted/updated 信号常量
  ├─ extend_bdd_instructions          # 新增 LiveView 测试指令（或决定使用 LiveViewTest）
  ├─ write_bdd_dsl                    # 依赖: extend_bdd_instructions
  ├─ implement_backend_api            # 依赖: extend_signal_types
  │   ├─ add_store_delete_observation
  │   └─ add_store_update_observation
  ├─ implement_liveview               # 依赖: implement_backend_api
  │   ├─ create_memory_live_index     # 含按日期分组逻辑（Helper 函数）
  │   ├─ update_router
  │   └─ update_app_layout
  └─ verify_bdd                       # 依赖: write_bdd_dsl + implement_liveview
```

> **注意**：`load_observations_by_date` 的按日期分组逻辑为纯数据变换，不放入 `Memory.Store` GenServer，
> 而是在 LiveView 层通过 Helper 函数实现（见第七节）。

---

## 五、BDD 场景定义

### 文件位置
`test/bdd/dsl/memory_ui.dsl`

### 核心场景

#### 场景 1：查看工作记忆
```bdd
FEATURE Memory UI - 记忆系统网页界面

SCENARIO 查看工作记忆
  GIVEN 工作记忆中有 focus 和 2 个 curiosities
  WHEN 用户访问 /memory 页面
  THEN 应该看到工作记忆内容
  AND 应该看到删除和清空按钮
```

#### 场景 2：删除单条观察项
```bdd
SCENARIO 删除单条观察项
  GIVEN 观察存储中有 3 条观察项
  WHEN 用户删除第 2 条观察项
  THEN 观察存储应该只剩 2 条
  AND 应该发射 memory.observation.deleted 信号
```

#### 场景 3：按日期分组展示观察项
```bdd
SCENARIO 按日期分组展示观察项
  GIVEN 观察存储中有跨 3 天的 10 条观察项
  WHEN 用户访问观察项 Tab
  THEN 应该按日期分组展示
  AND 每个日期组内按优先级排序
```

#### 场景 4：编辑 MEMORY.md 文件
```bdd
SCENARIO 编辑 MEMORY.md 文件
  GIVEN MEMORY.md 文件存在
  WHEN 用户修改内容并保存
  THEN 文件应该更新
  AND 内容应该持久化到磁盘
```

#### 场景 5：实时信号更新
```bdd
SCENARIO 实时信号更新
  GIVEN 用户正在查看工作记忆 Tab
  WHEN 系统发射 memory.working.saved 信号
  THEN LiveView 应该自动刷新显示
```

#### 场景 6：清空工作记忆
```bdd
SCENARIO 清空工作记忆
  GIVEN 工作记忆中有 focus 和 3 个 curiosities
  WHEN 用户点击清空全部按钮
  THEN 工作记忆应该为空
  AND 页面应该显示空状态提示
```

#### 场景 7：接受提议
```bdd
SCENARIO 接受提议
  GIVEN 提议队列中有 2 条 pending 提议
  WHEN 用户接受第 1 条提议
  THEN 提议状态应该变为 accepted
  AND 应该发射 memory.proposal.accepted 信号
  AND 观察项列表应该新增一条记录
```

#### 场景 8：拒绝提议
```bdd
SCENARIO 拒绝提议
  GIVEN 提议队列中有 2 条 pending 提议
  WHEN 用户拒绝第 1 条提议
  THEN 提议状态应该变为 rejected
  AND 提议队列应该只剩 1 条 pending
```

#### 场景 9：编辑观察项内容
```bdd
SCENARIO 编辑观察项内容
  GIVEN 观察存储中有 1 条内容为 "原始内容" 的观察项
  WHEN 用户将内容修改为 "更新后内容" 并保存
  THEN 观察项内容应该为 "更新后内容"
  AND 应该发射 memory.observation.updated 信号
```

#### 场景 10：防级联保护
```bdd
SCENARIO 信号回调不触发新信号
  GIVEN 用户正在查看观察项 Tab
  WHEN 系统发射 memory.observation.created 信号
  THEN LiveView 应该刷新数据
  AND 刷新过程不应该发射任何新信号
```

---

## 六、后端 API 扩展

### Memory.Store 新增函数

#### 1. 删除单条观察项
```elixir
@doc """
删除单条观察项。

## 参数
- `observation_id` - 观察项 ID
- `server` - GenServer 名称（默认 `__MODULE__`）

## 信号
操作完成后发射 `memory.observation.deleted` 信号。
"""
def delete_observation(observation_id, server \\ __MODULE__)
```

#### 2. 更新单条观察项
```elixir
@doc """
更新单条观察项内容。

## 参数
- `observation_id` - 观察项 ID
- `new_content` - 新内容
- `server` - GenServer 名称（默认 `__MODULE__`）

## 信号
操作完成后发射 `memory.observation.updated` 信号。
"""
def update_observation(observation_id, new_content, server \\ __MODULE__)
```

> **注意**：原计划中的 `load_observations_by_date/1` 已移至 LiveView 层实现（见第七节 Helper 函数），
> 因为按日期分组是纯数据变换，不需要经过 GenServer 调用。

### SignalTypes 新增
```elixir
# lib/cortex/memory/signal_types.ex
def memory_observation_deleted, do: "memory.observation.deleted"
def memory_observation_updated, do: "memory.observation.updated"
```

---

## 七、LiveView 实现

### 文件结构
```
lib/cortex_web/live/memory_live/
  index.ex          # 主 LiveView（包含内联模板）
```

### 页面结构：4 个 Tab

#### Tab 1 — 工作记忆 (Working Memory)
- **数据源**：`WorkingMemory.list_all/0`
- **展示内容**：
  - Focus（当前焦点）
  - Curiosities（好奇心队列）
  - Concerns（顾虑列表）
  - Goals（目标列表）
- **操作**：
  - 删除单项：`WorkingMemory.remove/1`
  - 清空全部：`WorkingMemory.clear/0`
- **实时更新**：订阅 `memory.working.saved`

#### Tab 2 — 观察项 (Observations)
- **数据源**：`Memory.Store.load_observations/1` + LiveView 层 Helper 分组
- **展示方式**：
  - 按日期分组（默认最近 7 天）
  - 每个日期组内按优先级排序（🔴🟡🟢）
  - 支持展开/折叠日期组
  - 使用 LiveView Streams 渲染列表（避免大列表性能问题）
- **操作**：
  - 删除单条：`Store.delete_observation/2`
  - 编辑内容：`Store.update_observation/3`
  - 按优先级过滤
- **实时更新**：订阅 `memory.observation.created`, `memory.observation.deleted`, `memory.observation.updated`

**按日期分组 Helper 函数**（在 LiveView 模块内实现）：
```elixir
defp group_observations_by_date(observations, days \\ 7) do
  cutoff = Date.add(Date.utc_today(), -days)

  observations
  |> Enum.filter(fn obs -> Date.compare(DateTime.to_date(obs.timestamp), cutoff) != :lt end)
  |> Enum.group_by(fn obs -> DateTime.to_date(obs.timestamp) end)
  |> Enum.sort_by(fn {date, _} -> date end, {:desc, Date})
end
```

#### Tab 3 — 提议队列 (Proposals)
- **数据源**：`Proposal.list_pending/1`（接受 opts keyword list，如 `limit:`, `min_confidence:`, `order_by:`）
- **展示内容**：
  - 提议类型（fact/insight/learning/pattern/preference）
  - 置信度
  - 内容预览
- **操作**：
  - Accept：`Store.accept_proposal/2`（第二参数 server 默认 `__MODULE__`）
  - Reject：`Proposal.reject/1`
- **实时更新**：订阅 `memory.proposal.created`
- **防抖机制**：Accept 操作会触发 3 个信号（`proposal.accepted` + `kg.node_added` + `observation.created`），
  LiveView 使用 `Process.send_after(self(), :debounced_reload, 100)` 合并短时间内的多次刷新，避免 UI 闪烁。

#### Tab 4 — 全局记忆文件 (MEMORY.md)
- **数据源**：`Cortex.Memory.load_memory/2`
- **展示方式**：
  - Textarea 编辑器
  - Global / Workspace 两级切换
- **操作**：
  - 保存：`Cortex.Memory.update_memory/4`（签名：`update_memory(workspace_root, level, content, workspace_id \\ nil)`）
- **安全约束**：LiveView 层限制 `level` 参数只能为 `:global` 或 `:workspace`，
  并在 `mount/3` 中从 `Workspaces.workspace_root()` 获取 `workspace_root` 存入 assigns。
  > **TODO**：`Cortex.Memory.update_memory/4` 当前未使用 `Security.validate_path` 进行沙箱校验，
  > 实施时需补充路径安全校验，与 `Memory.Store` 保持一致。

### 信号订阅机制
```elixir
def mount(_params, _session, socket) do
  # 订阅信号
  SignalHub.subscribe("memory.working.saved")
  SignalHub.subscribe("memory.observation.created")
  SignalHub.subscribe("memory.observation.deleted")
  SignalHub.subscribe("memory.observation.updated")
  SignalHub.subscribe("memory.proposal.created")
  
  {:ok, assign(socket,
    active_tab: :working,
    workspace_root: Workspaces.workspace_root(),
    ...
  )}
end

# 防级联保护：所有 reload_* 函数均为纯读操作，不发射任何信号。
# 防抖机制：短时间内多次信号触发时，合并为一次 UI 刷新。
def handle_info({:signal, %Jido.Signal{type: type}}, socket) do
  case type do
    "memory.working.saved" ->
      schedule_debounced_reload(socket, :working)
    "memory.observation." <> _ ->
      schedule_debounced_reload(socket, :observations)
    "memory.proposal.created" ->
      schedule_debounced_reload(socket, :proposals)
    _ ->
      {:noreply, socket}
  end
end

def handle_info({:debounced_reload, target}, socket) do
  case target do
    :working -> {:noreply, reload_working_memory(socket)}
    :observations -> {:noreply, reload_observations(socket)}
    :proposals -> {:noreply, reload_proposals(socket)}
  end
end

defp schedule_debounced_reload(socket, target) do
  # 取消之前的定时器（如果有），100ms 内合并多次信号
  timer_key = :"reload_timer_#{target}"
  if old_timer = socket.assigns[timer_key], do: Process.cancel_timer(old_timer)
  timer = Process.send_after(self(), {:debounced_reload, target}, 100)
  {:noreply, assign(socket, timer_key, timer)}
end
```

---

## 八、路由与导航

### Router 修改
```elixir
# lib/cortex_web/router.ex
# 注意：保持现有的编译期条件分支结构，仅在 live_session :admin 块内新增路由
scope "/", CortexWeb do
  if Application.compile_env(:cortex, :require_admin, true) do
    pipe_through [:browser, :require_admin]
  else
    pipe_through :browser
  end
  
  live_session :admin, on_mount: [], layout: {CortexWeb.Layouts, :app} do
    live "/", JidoLive, :index
    live "/memory", MemoryLive.Index, :overview  # 新增
    live "/settings", SettingsLive.Index, :channels
    # ...
  end
end
```

### App Layout 修改
```heex
<!-- lib/cortex_web/components/layouts/app.html.heex -->
<div class="border-t border-slate-800 p-3 space-y-1">
  <!-- 新增 Memory 按钮 -->
  <.link
    navigate="/memory"
    class={[
      "flex items-center gap-3 px-3 py-2 rounded-lg transition-colors",
      @active_tab == :memory && "bg-teal-600/10 text-teal-400",
      @active_tab != :memory && "text-slate-400 hover:bg-slate-800 hover:text-white"
    ]}
  >
    <.icon name="hero-light-bulb" class="w-5 h-5" />
    <span class="text-sm font-medium">Memory</span>
  </.link>
  
  <.link navigate="/settings/channels" class="...">
    <.icon name="hero-cog-6-tooth" class="w-5 h-5" />
    <span class="text-sm font-medium">Settings</span>
  </.link>
  
  <!-- ... -->
</div>
```

---

## 九、性能优化策略（参考 Hmem）

### LiveView Streams（P0 即采用）
- 所有列表渲染（工作记忆、观察项、提议队列）从 P0 阶段即使用 LiveView Streams
- Streams 是 LiveView 标准列表渲染方式，不增加复杂度，且天然支持高效增删

### 分页加载
- 观察项列表默认加载最近 7 天
- 支持"加载更多"按钮加载更早的记忆

### 懒加载详情
- 列表只显示摘要（前 100 字符）
- 点击展开完整内容

### 信号防抖
- LiveView 信号回调使用 100ms 防抖窗口，合并短时间内的多次信号触发为一次 UI 刷新
- 避免 Accept Proposal 等操作触发多个信号导致 UI 闪烁

---

## 十、验证与门禁

### BDD 编译与测试
```bash
# 1. 编译 DSL 生成测试
bddc compile --instructions priv/bdd/instructions_v1.exs

# 2. 运行生成的测试
mix test test/bdd_generated/memory_ui_test.exs

# 3. BDD 门禁
./scripts/bdd_gate.sh

# 4. 全量检查
./scripts/pre_deploy_check.sh
```

### 需要的 BDD 指令集

经核查 `priv/bdd/instructions_v1.exs`，现有指令集中：
- `assert_signal_emitted` — **已存在** ✅
- `visit_page(path)` — **不存在** ❌
- `assert_element_exists(selector)` — **不存在** ❌
- `click_button(text)` — **不存在** ❌
- `assert_count(collection, expected)` — **不存在** ❌

**决策**：LiveView UI 交互测试所需的指令集大部分缺失，这是实施阻塞项。采用双轨策略：
1. **后端逻辑测试**：使用现有 BDD 指令集（信号发射、数据变更断言）
2. **UI 交互测试**：使用标准 `Phoenix.LiveViewTest`（`render_click`、`render_change` 等），不依赖 BDDC

如果后续需要将 LiveView 测试也纳入 BDD 体系，再扩展指令集。

---

## 十一、实施优先级

### P0（核心功能 + 阻塞项）
- [x] 规划文档生成
- [ ] 新增 SignalTypes 常量（`memory.observation.deleted`、`memory.observation.updated`）
- [ ] BDD DSL 场景编写（后端逻辑部分）
- [ ] LiveView UI 测试编写（使用 `Phoenix.LiveViewTest`）
- [ ] Tab 1（工作记忆）实现（使用 LiveView Streams）
- [ ] Tab 4（MEMORY.md 编辑）实现（含路径安全校验）
- [ ] 路由与导航集成

### P1（主要功能）
- [ ] 后端 API 扩展（delete/update observation）
- [ ] Tab 2（观察项 + LiveView 层按日期分组）实现
- [ ] 实时信号订阅与防抖刷新

### P2（高级功能）
- [ ] Tab 3（提议队列）实现
- [ ] 编辑观察项内容功能

### P3（性能优化）
- [ ] 懒加载详情
- [ ] 分页加载更早记忆

---

## 十二、不实施的内容

- **不新增 KnowledgeGraph 的 UI**：内部结构复杂，非用户直接操作对象
- **不新增 Preconscious 的 UI**：纯后台进程
- **暂不改为按日期分文件存储**：保持当前单文件架构，UI 层做分组展示即可

---

## 十三、风险与依赖

### 技术风险
- **LiveView 性能**：如果观察项超过 1000 条，需要虚拟滚动（P0 已采用 Streams 缓解）
- **信号风暴**：频繁的信号更新可能导致 UI 闪烁（已通过 100ms 防抖机制解决）
- **防级联保护**：LiveView 信号回调中的 reload 函数必须为纯读操作，禁止发射新信号
- **路径安全**：`Cortex.Memory.update_memory/4` 未使用 `Security.validate_path`，需在实施时补充
- **Proposal ETS 竞态**：当前 Proposal 操作直接走 ETS（`:public`），单用户场景无问题，多用户场景可能出现竞态（V2 考虑）

### 依赖项
- Phoenix LiveView 已集成
- SignalHub 已实现
- BDDC 工具链已就绪

### 阻塞项（已解决）
- ~~BDD 指令集缺失~~：采用双轨策略，后端逻辑用 BDD，UI 交互用 `Phoenix.LiveViewTest`
- ~~API 签名不一致~~：已在本文档中修正为实际签名

---

## 十四、后续迭代方向

### V2 功能
- 搜索与过滤（全文搜索观察项）
- 导出记忆（Markdown/JSON）
- 记忆统计图表（按日期/优先级分布）

### V3 功能
- 知识图谱可视化（D3.js）
- 记忆回放（时间轴）
- 多工作区记忆对比

---

## 附录：参考资料

- [AGENTS.md](../../AGENTS.md) - Cortex 架构指南
- [BDDC Skill](../../.agent/skills/bddc/SKILL.md) - BDD 工作流
- [Feature Iteration Prompt](../../.agent/prompts/feature_iteration.md) - 迭代规范
- [Memory System Doc](../MEMORY_SYSTEM.md) - 记忆系统架构
- [Hmem Architecture](https://github.com/Bumblebiber/hmem) - 分层记忆参考
- [Nanobot Memory](https://jinlow.medium.com/nanobot-architecture-teardown-4-000-lines-achieving...) - Stateful Memory 参考
