# BDD 测试转换可行性分析

> 日期：2026-02-19
> 目标：分析现有手写测试中哪些适合转换为 BDDC DSL 场景，纳入 `bdd_gate.sh` 门禁

---

## 一、现状概览

| 类别 | 数量 | 说明 |
|---|---|---|
| 手写 ExUnit 测试 | 64 个文件 | `test/cortex/` + `test/cortex_web/` + `test/integration/` |
| 已有 BDD DSL 场景 | 20 个 `.dsl` 文件 | `test/bdd/dsl/` |
| BDD 生成测试 | 17 个 `_generated_test.exs` | `test/bdd_generated/` |

## 二、已被 BDD 覆盖的领域（无需重复转换）

以下领域已有对应 DSL，**不建议重复转换**：

- ✅ 安全沙箱 (`sandbox.dsl`) — 对应 `security_test.exs`
- ✅ 重试分类 (`retry.dsl`) — 对应 `retry_test.exs`
- ✅ Steering 队列 (`steering.dsl`) — 对应 `steering_test.exs`
- ✅ Token 截断 (`truncate.dsl`, `token_optimization.dsl`) — 对应 `truncate_test.exs`, `token_budget_test.exs`
- ✅ 信号审计 (`audit_noise_reduction.dsl`) — 对应 `signal_recorder_test.exs`
- ✅ 扩展生命周期 (`extension_lifecycle.dsl`) — 对应 `hook_registry_test.exs`
- ✅ 后台检查 (`p1_background_checks.dsl`) — 对应 `background_checks_test.exs`
- ✅ 多 Agent 协调 (`multi_agent_coordination.dsl`) — 对应 `coding_coordinator_test.exs`

## 三、🟢 强烈推荐转换（HIGH）— 未被 DSL 覆盖的行为型测试

这些测试具有清晰的 **Given-When-Then** 模式，且无对应 DSL，最适合转换：

### 第一优先级（核心业务行为）

| 测试文件 | 建议 DSL 名 | 场景数(估) | 理由 |
|---|---|---|---|
| `signal_hub_test.exs` | `signal_hub_core.dsl` | 8-10 | 信号总线是 V3 架构核心，订阅/发射/字段校验全是行为规则 |
| `permission_tracker_test.exs` | `permission_lifecycle.dsl` | 5-6 | ask→allow/deny/allow_always 状态机，教科书级 BDD 场景 |
| `shell_interceptor_test.exs` | `shell_security.dsl` | 6-8 | 命令分类规则（安全/需审批），每条都是独立行为场景 |
| `session/coordinator_test.exs` | `session_lifecycle.dsl` | 8-10 | 会话生命周期（ensure/stop/switch/save），核心工作流 |
| `session/branch_manager_test.exs` | `session_branching.dsl` | 4-5 | 分支创建+信号验证，与已有 tape_branching.dsl 互补 |

### 第二优先级（文件工具行为）

| 测试文件 | 建议 DSL 名 | 场景数(估) | 理由 |
|---|---|---|---|
| `tools/handlers/edit_file_test.exs` | `edit_file_behavior.dsl` | 5-6 | 授权编辑/拒绝编辑，安全边界行为 |
| `tools/handlers/read_file_test.exs` | `read_file_behavior.dsl` | 4-5 | 沙箱路径授权，与 sandbox.dsl 互补 |

### 第三优先级（Memory 系统行为）

| 测试文件 | 建议 DSL 名 | 场景数(估) | 理由 |
|---|---|---|---|
| `memory/integration_test.exs` | `memory_e2e.dsl` | 5-6 | observation→store→context→graph 端到端工作流 |
| `memory/proposal_test.exs` | `memory_proposal.dsl` | 6-8 | 提议生命周期（create→accept/reject），状态转换 |
| `memory/subconscious_test.exs` | `memory_subconscious.dsl` | 5-6 | 偏好提取行为规则 |

### 第四优先级（通道/集成行为）

| 测试文件 | 建议 DSL 名 | 场景数(估) | 理由 |
|---|---|---|---|
| `channels/shared/policy_test.exs` | `channel_access_policy.dsl` | 8-10 | DM/群组访问策略（open/whitelist/blacklist/mention）|
| `channels/config_loader_test.exs` | `channel_config_merge.dsl` | 4-5 | 配置优先级 DB > JSON > Env |
| `channels/telegram/echo_bridge_test.exs` | `telegram_echo.dsl` | 2-3 | 信号驱动回声桥 |
| `conversations_test.exs` | `conversation_lifecycle.dsl` | 6-8 | 对话 CRUD + 信号发射验证 |
| `conversations_display_test.exs` | `display_message_lifecycle.dsl` | 4-5 | pending→completed 状态流转 |
| `feishu_webhook_controller_test.exs` | `feishu_webhook_auth.dsl` | 2-3 | Token 验证安全行为 |

## 四、🟡 中等优先级（MEDIUM）— 可考虑部分转换

这些测试有行为化倾向，但部分场景过于技术化，建议**提取关键行为场景**转 BDD，保留纯单元部分：

| 测试文件 | 可转换部分 | 保留手写的部分 |
|---|---|---|
| `tools/v3_tools_test.exs` | 工具调用成功/失败行为 | 输出格式细节 |
| `agents/llm_agent_test.exs` | 对话流程、模型切换行为 | Mock 细节、流式内部状态 |
| `history/dual_track_filter_test.exs` | 信号可见性分类规则 | 过滤器内部实现 |
| `config/llm_resolver_test.exs` | 解析回退规则 | 缓存细节 |
| `workspaces/snapshot_manager_test.exs` | 备份/恢复策略 | 文件系统细节 |
| `memory/knowledge_graph_test.exs` | 节点/边 CRUD 行为 | 序列化格式 |

## 五、🔴 不建议转换（LOW）— 保留为手写单元测试

| 测试文件 | 理由 |
|---|---|
| `agents/steering_test.exs` | 纯数据结构操作 (queue) |
| `agents/retry_test.exs` | 纯函数映射（已有 DSL 覆盖） |
| `memory/observation_test.exs` | 结构体序列化/反序列化 |
| `memory/cognitive_prompts_test.exs` | 简单字符串查找 |
| `channels/shared/text_chunker_test.exs` | 纯工具函数 |
| `session/factory_test.exs` | Options builder |
| `extensions/context_test.exs` | 结构体映射 |
| `dingtalk/client_test.exs` | 占位测试（空） |
| `dingtalk/receiver_test.exs` | 占位测试（空） |
| `dingtalk/dispatcher_test.exs` | 占位测试（空） |
| `llm/llmdb_custom_test.exs` | 占位测试（空） |

## 六、推荐实施路线

```
Phase 1 (立即)  → signal_hub_core + permission_lifecycle + shell_security
Phase 2 (本周)  → session_lifecycle + session_branching + edit/read_file_behavior
Phase 3 (下周)  → memory_e2e + memory_proposal + channel_access_policy
Phase 4 (迭代)  → conversation_lifecycle + 其余 HIGH 项
```

### 转换后 `bdd_gate.sh` 预期效果

- 当前：20 个 DSL → ~17 个生成测试
- Phase 1 后：23 个 DSL → ~20 个生成测试（+核心信号/安全覆盖）
- 全部完成：~36 个 DSL → ~33 个生成测试（覆盖全部核心行为）

### 转换注意事项

1. **不要删除原始手写测试**，先让 BDD 测试与手写测试并行运行
2. 转换时需先在 `priv/bdd/instructions_v1.exs` 中注册新指令
3. 每个 DSL 文件需确保 `bddc compile` 通过后再纳入门禁
4. 复杂 Mock 场景（如 `llm_agent_test.exs`）需先评估指令是否支持
