# Sprint 1 Token 优化 BDD 测试
# Code Skimming (分级读取) & Context Truncation (上下文截断)

[SCENARIO: BDD-TRUNC-001] TITLE: 智能上下文截断 (Context Truncation) TAGS: integration agent truncate
# 模拟一个超长的对话历史
GIVEN start_agent session_id="trunc_test"
WHEN steering_inject content="Long user message 1"
WHEN steering_inject content="Long user message 2"
WHEN steering_inject content="Long user message 3"
THEN assert_agent_history_count session_id="trunc_test" min_count=3

