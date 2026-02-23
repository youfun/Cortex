# Tape 集成测试
# 验证 Agent 从 Tape 恢复状态

[SCENARIO: TAPE-INTEGRATION-001] TITLE: 从 Tape 恢复上下文 TAGS: integration tape
GIVEN signal_bus_is_clean
# 我们不依赖真实的 LLM 交互，而是手动制造历史记录
# Tape.Store 会记录这些信号

# 1. 模拟用户输入
WHEN signal_is_emitted type="agent.chat.request" data='{"content":"User Message 1","session_id":"integration_session"}' session_id="integration_session"

# 2. 模拟 Agent 响应
WHEN signal_is_emitted type="agent.response" data='{"content":"Assistant Message 1","session_id":"integration_session"}' session_id="integration_session"

# 3. 验证 Tape 记录了这些
THEN tape_should_contain_entry type="agent.chat.request" session_id="integration_session"
THEN tape_should_contain_entry type="agent.response" session_id="integration_session"

# 4. 启动 Agent (它应该在初始化时读取 Tape)
# 我们使用相同的 session_id
GIVEN start_agent session_id="integration_session"

# 5. 验证 Agent 内部已恢复历史记录
# 应该有 1 个 User 消息 + 1 个 Assistant 消息 + 1 个 System Prompt (LLMAgent 自动添加)
# 所以 full_history 至少有 2 个条目 (System 消息也会记录在 full_history 中)
# LLMAgent.init -> restore -> add system prompt
THEN assert_agent_history_count session_id="integration_session" min_count=2

# 6. 重启 Agent
WHEN restart_agent session_id="integration_session"

# 7. 再次验证
THEN assert_agent_history_count session_id="integration_session" min_count=2
