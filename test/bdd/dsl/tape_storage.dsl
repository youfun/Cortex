# Tape 存储核心 BDD 测试
# 验证 Tape 的追加逻辑

[SCENARIO: TAPE-CORE-001] TITLE: 记录 Agent 响应 TAGS: integration tape
GIVEN signal_bus_is_clean
WHEN signal_is_emitted type="agent.response" data='{"content":"Hello Tape"}'
THEN tape_should_contain_entry type="agent.response"

[SCENARIO: TAPE-CORE-002] TITLE: 忽略无关信号 TAGS: integration tape
GIVEN signal_bus_is_clean
WHEN signal_is_emitted type="some.noise" data='{"noise":"level 9000"}'
THEN tape_should_not_contain_entry type="some.noise"

[SCENARIO: TAPE-CORE-003] TITLE: 验证 Limit 参数 TAGS: integration tape
GIVEN signal_bus_is_clean
WHEN signal_is_emitted type="agent.response" data='{"content":"Msg 1"}' session_id="limit_test"
WHEN signal_is_emitted type="agent.response" data='{"content":"Msg 2"}' session_id="limit_test"
WHEN signal_is_emitted type="agent.response" data='{"content":"Msg 3"}' session_id="limit_test"
# Verify we can get all 3
THEN tape_entry_count_should_be session_id="limit_test" expected=3
# Verify limit works
THEN tape_entry_count_should_be session_id="limit_test" limit=2 expected=2

