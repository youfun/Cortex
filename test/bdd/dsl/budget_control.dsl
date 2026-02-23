# Budget Control BDD 测试
# 验证 Token 预算控制和自动限流

[SCENARIO: BC-001] TITLE: 预算内文本通过检查 TAGS: unit budget
LET short_text = "Short text"
WHEN estimate_tokens text=$short_text
THEN assert_tokens expected=4

[SCENARIO: BC-002] TITLE: 消息列表 Token 统计 TAGS: unit budget
LET messages = '[{"role":"user","content":"Hello world"},{"role":"assistant","content":"Hi there friend"}]'
WHEN estimate_messages messages=$messages
THEN assert_total_tokens expected=10

[SCENARIO: BC-003] TITLE: 短对话预算检查通过 TAGS: integration budget agent
# 构造一个短对话，应该在预算内
GIVEN start_agent session_id="bc_003"
WHEN steering_inject content="Hello, how are you?"
WHEN steering_inject content="I am fine, thank you"
THEN assert_agent_history_count session_id="bc_003" min_count=2
