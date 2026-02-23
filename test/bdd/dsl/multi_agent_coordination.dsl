# Multi-Agent Coordination BDD Scenarios
# Sprint 3: Spawn Handshake 多 Agent 协调

[SCENARIO: MULTI-AGENT-001] TITLE: 成功完成编码任务（一次通过） TAGS: integration multi_agent coordination
GIVEN signal_bus_is_clean
WHEN signal_is_emitted type="coding.task.requested" data='{"task":"实现用户登录功能","session_id":"multi_agent_001"}' session_id="multi_agent_001"
WHEN signal_is_emitted type="coding.task.stage" data='{"stage":"analyzing","session_id":"multi_agent_001"}' session_id="multi_agent_001"
WHEN signal_is_emitted type="coding.task.stage" data='{"stage":"implementing","session_id":"multi_agent_001"}' session_id="multi_agent_001"
WHEN signal_is_emitted type="coding.task.stage" data='{"stage":"reviewing","session_id":"multi_agent_001"}' session_id="multi_agent_001"
WHEN signal_is_emitted type="coding.task.completed" data='{"session_id":"multi_agent_001"}' session_id="multi_agent_001"
THEN history_file_should_contain type="coding.task.requested"
THEN history_file_should_contain type="coding.task.stage"
THEN history_file_should_contain type="coding.task.completed"

[SCENARIO: MULTI-AGENT-002] TITLE: 审查失败后重试成功 TAGS: integration multi_agent retry
GIVEN signal_bus_is_clean
WHEN signal_is_emitted type="coding.task.requested" data='{"task":"实现数据验证","session_id":"multi_agent_002"}' session_id="multi_agent_002"
WHEN signal_is_emitted type="coding.task.review.failed" data='{"attempt":1,"session_id":"multi_agent_002"}' session_id="multi_agent_002"
WHEN signal_is_emitted type="coding.task.retry" data='{"attempt":2,"session_id":"multi_agent_002"}' session_id="multi_agent_002"
WHEN signal_is_emitted type="coding.task.completed" data='{"total_attempts":2,"session_id":"multi_agent_002"}' session_id="multi_agent_002"
THEN history_file_should_contain type="coding.task.review.failed"
THEN history_file_should_contain type="coding.task.retry"
THEN history_file_should_contain type="coding.task.completed"

[SCENARIO: MULTI-AGENT-003] TITLE: 超过最大重试次数 TAGS: integration multi_agent retry
GIVEN signal_bus_is_clean
WHEN signal_is_emitted type="coding.task.requested" data='{"task":"实现复杂算法","max_attempts":3,"session_id":"multi_agent_003"}' session_id="multi_agent_003"
WHEN signal_is_emitted type="coding.task.review.failed" data='{"attempt":1,"session_id":"multi_agent_003"}' session_id="multi_agent_003"
WHEN signal_is_emitted type="coding.task.review.failed" data='{"attempt":2,"session_id":"multi_agent_003"}' session_id="multi_agent_003"
WHEN signal_is_emitted type="coding.task.review.failed" data='{"attempt":3,"session_id":"multi_agent_003"}' session_id="multi_agent_003"
WHEN signal_is_emitted type="coding.task.failed" data='{"status":"max_retries_exceeded","session_id":"multi_agent_003"}' session_id="multi_agent_003"
THEN history_file_should_contain type="coding.task.review.failed"
THEN history_file_should_contain type="coding.task.failed"

[SCENARIO: MULTI-AGENT-004] TITLE: 子 Agent 崩溃处理 TAGS: integration multi_agent failure
GIVEN signal_bus_is_clean
WHEN signal_is_emitted type="coding.task.requested" data='{"task":"实现文件上传","session_id":"multi_agent_004"}' session_id="multi_agent_004"
WHEN signal_is_emitted type="coding.task.child_crash" data='{"error":"child_crash","session_id":"multi_agent_004"}' session_id="multi_agent_004"
WHEN signal_is_emitted type="coding.task.failed" data='{"status":"child_crash","session_id":"multi_agent_004"}' session_id="multi_agent_004"
THEN history_file_should_contain type="coding.task.child_crash"
THEN history_file_should_contain type="coding.task.failed"

[SCENARIO: MULTI-AGENT-005] TITLE: Spawn Handshake 两阶段启动 TAGS: integration multi_agent spawn
GIVEN signal_bus_is_clean
WHEN signal_is_emitted type="coding.task.requested" data='{"task":"实现搜索功能","session_id":"multi_agent_005"}' session_id="multi_agent_005"
WHEN signal_is_emitted type="coding.task.spawn.requested" data='{"session_id":"multi_agent_005"}' session_id="multi_agent_005"
WHEN signal_is_emitted type="jido.agent.child.started" data='{"session_id":"multi_agent_005"}' session_id="multi_agent_005"
WHEN signal_is_emitted type="coding.task.work.requested" data='{"session_id":"multi_agent_005"}' session_id="multi_agent_005"
THEN history_file_should_contain type="coding.task.spawn.requested"
THEN history_file_should_contain type="jido.agent.child.started"
THEN history_file_should_contain type="coding.task.work.requested"
