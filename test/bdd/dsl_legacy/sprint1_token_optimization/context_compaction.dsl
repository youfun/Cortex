# Sprint 1 Token 优化 - Context Compaction 增强场景
# Feature: Enhanced Context Compaction with Tiered Compression

[SCENARIO: COMP-001] TITLE: Trigger Tier 1 compression when context exceeds soft threshold TAGS: integration compaction token
GIVEN 历史对话已超过模型上下文阈值的 80%
GIVEN 存在多条旧的 tool 消息
WHEN Compaction.maybe_compact/3 被调用
THEN 应执行 Tier 1 压缩（截断工具输出）
THEN 旧的 tool 消息输出应被截断到 2000 字符
THEN 截断后的消息应包含 "[Output truncated for brevity]" 标识
THEN 如果截断后在预算内，应返回成功

[SCENARIO: COMP-002] TITLE: Trigger Tier 2 LLM summarization when Tier 1 is insufficient TAGS: integration compaction token
GIVEN 历史对话已超过模型上下文阈值的 80%
GIVEN Tier 1 压缩后仍超过阈值
WHEN Compaction.compact/3 执行 Tier 2 压缩
THEN 应调用 LLM 对旧消息进行摘要
THEN 摘要消息应包含 "[Context Summary]" 标识
THEN 摘要应保留关键决策、文件路径、工具结果和任务状态
THEN system 消息应被保留在摘要之前
THEN 最近的消息应被保留在摘要之后

[SCENARIO: COMP-003] TITLE: Trigger Tier 3 force drop when context exceeds hard limit TAGS: integration compaction token
GIVEN 历史对话已超过模型上下文阈值的 95%（硬限制）
WHEN Compaction.maybe_compact/3 被调用
THEN 应直接执行 Tier 3 强制丢弃
THEN system 消息永远不被丢弃
THEN 最后一条 user 消息永远不被丢弃
THEN 其他消息按权重排序后优先丢弃低权重消息
THEN 最终上下文应降到 90% 以下

[SCENARIO: COMP-004] TITLE: Protect high-priority messages based on role weights TAGS: unit compaction token
GIVEN 需要进行消息丢弃
GIVEN 存在 system、user、assistant、tool 各类消息
WHEN Compaction.force_drop/3 执行权重排序
THEN system 消息权重应为无穷大（永不丢弃）
THEN 最后一条 user 消息权重应为无穷大（永不丢弃）
THEN 历史 user 消息权重应为 3（高优先级）
THEN assistant 消息权重应为 2（中优先级）
THEN tool 消息权重应为 1（低优先级，最先丢弃）

[SCENARIO: COMP-005] TITLE: Fallback to Tier 3 when LLM summarization fails TAGS: integration compaction token
GIVEN Tier 2 LLM 摘要被触发
GIVEN LLM 调用返回错误（如网络超时或 API 错误）
WHEN 摘要失败
THEN 应自动降级到 Tier 3 强制丢弃
THEN 不应抛出错误导致 Agent 中断

[SCENARIO: COMP-006] TITLE: Handle empty message history gracefully TAGS: unit compaction token
GIVEN 历史消息列表为空或只有 system 消息
WHEN Compaction.compact/3 被调用
THEN 应直接返回原始上下文
THEN 不应尝试摘要或丢弃

[SCENARIO: COMP-007] TITLE: Preserve tool call metadata when truncating outputs TAGS: unit compaction tool
GIVEN 一条 tool 消息的输出超过 2000 字符
WHEN 执行 truncate_tool_outputs/1
THEN 输出应被截断到 2000 字符
THEN 应保留前 2000 字符的内容
THEN 应添加 "[Output truncated for brevity]" 后缀
THEN tool_call_id 和其他元信息应被保留

[SCENARIO: COMP-008] TITLE: Progressive compression across multiple conversation turns TAGS: integration compaction token
GIVEN 一个长时间运行的对话会话
GIVEN 每轮对话都添加新的消息
WHEN 上下文逐渐增长并多次触发压缩
THEN 第一次应执行 Tier 1 压缩
THEN 后续如果仍超限应执行 Tier 2 摘要
THEN 最终如果仍超限应执行 Tier 3 丢弃
THEN 每次压缩后的上下文应能正常继续对话

[SCENARIO: COMP-009] TITLE: Preserve recent messages with sliding window TAGS: unit compaction token
GIVEN 需要压缩的历史消息
GIVEN 配置的 keep_recent 参数为 15
WHEN SlidingWindow.split/2 分割消息
THEN 最近的 15 条消息应被保留
THEN 只有更早的消息会被压缩或丢弃
THEN system 消息应始终在保留区域

[SCENARIO: COMP-010] TITLE: Check context budget before and after compression TAGS: integration compaction token
GIVEN 一个包含大量消息的上下文
WHEN 执行任何级别的压缩
THEN 压缩前应计算当前 Token 消耗
THEN 压缩后应验证 Token 消耗是否在预算内
THEN 如果仍超预算应继续下一级压缩
THEN 最终结果应保证不超过模型上下文限制
