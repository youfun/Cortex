# Token Optimization BDD 测试
# Token 计数与滑动窗口管理

[SCENARIO: BDD-TOKEN-001] TITLE: 英文 Token 计数估算 TAGS: unit token
WHEN estimate_tokens text="Hello world"
THEN assert_tokens expected=4

[SCENARIO: BDD-TOKEN-002] TITLE: 中文 Token 计数估算 TAGS: unit token
WHEN estimate_tokens text="你好世界"
THEN assert_tokens expected=8

[SCENARIO: BDD-TOKEN-003] TITLE: 混合文本 Token 计数估算 TAGS: unit token
WHEN estimate_tokens text="Hello 你好"
THEN assert_tokens expected=7

[SCENARIO: BDD-WINDOW-001] TITLE: 滑动窗口基础分割 TAGS: unit window
WHEN sliding_window_split messages='[{"role":"user","content":"1"},{"role":"assistant","content":"2"},{"role":"user","content":"3"}]' window_size=2
THEN assert_window_size target="old" expected=1
THEN assert_window_size target="recent" expected=2

[SCENARIO: BDD-WINDOW-002] TITLE: 系统消息始终保留 TAGS: unit window
WHEN sliding_window_split messages='[{"role":"system","content":"sys"},{"role":"user","content":"1"},{"role":"assistant","content":"2"},{"role":"user","content":"3"}]' window_size=2
THEN assert_window_size target="old" expected=1
THEN assert_window_size target="recent" expected=3

[SCENARIO: BDD-WINDOW-003] TITLE: 安全边界保护：tool_call 配对 TAGS: unit window
WHEN sliding_window_split messages='[{"role":"user","content":"q"},{"role":"assistant","tool_calls":[{"id":"1"}]},{"role":"tool","tool_call_id":"1","content":"res"},{"role":"assistant","content":"done"}]' window_size=2
# 分割点本应在 idx=2 (tool result)，但触发保护，向前移到 idx=1 (assistant tool_calls)
THEN assert_window_size target="old" expected=1
THEN assert_window_size target="recent" expected=3

# Token Monitoring with Telemetry (T0.2)
[SCENARIO: BDD-MONITOR-001] TITLE: Token 使用监控基础功能 TAGS: unit monitoring
WHEN estimate_tokens text="Test message for monitoring"
THEN assert_tokens expected=9

[SCENARIO: BDD-MONITOR-002] TITLE: 消息列表 Token 统计 TAGS: unit monitoring
WHEN estimate_messages messages='[{"role":"user","content":"Hello"},{"role":"assistant","content":"Hi there"}]'
THEN assert_total_tokens expected=6
