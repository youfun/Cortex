# Steering BDD 测试
# 验证 Agent 在忙碌时正确入队 Steering 消息

[SCENARIO: STEERING-001] TITLE: 消息在 Agent 启动后入队 TAGS: integration steering
GIVEN start_agent
WHEN steering_inject content="Interrupt me!"
THEN assert_steering_queue_size expected=1

[SCENARIO: STEERING-002] TITLE: 多条消息顺序入队 TAGS: integration steering
GIVEN start_agent
WHEN steering_inject content="First"
WHEN steering_inject content="Second"
THEN assert_steering_queue_size expected=2
