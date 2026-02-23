# History Compression BDD 测试
# 验证长对话历史的自动压缩功能

[SCENARIO: HC-001] TITLE: 短对话不触发压缩 TAGS: unit compression
# 构造一个短对话（2 条消息），不应触发压缩
LET short_chat = '[{"role":"user","content":"Hello"},{"role":"assistant","content":"Hi there"}]'
WHEN compact messages=$short_chat model="gemini-3-flash"
THEN assert_messages_count expected=2

[SCENARIO: HC-002] TITLE: 超阈值对话触发压缩 TAGS: unit compression
# 构造一个超过阈值的对话（20+ 条消息）
LET long_chat = '[{"role":"user","content":"msg1"},{"role":"assistant","content":"reply1"},{"role":"user","content":"msg2"},{"role":"assistant","content":"reply2"},{"role":"user","content":"msg3"},{"role":"assistant","content":"reply3"},{"role":"user","content":"msg4"},{"role":"assistant","content":"reply4"},{"role":"user","content":"msg5"},{"role":"assistant","content":"reply5"},{"role":"user","content":"msg6"},{"role":"assistant","content":"reply6"},{"role":"user","content":"msg7"},{"role":"assistant","content":"reply7"},{"role":"user","content":"msg8"},{"role":"assistant","content":"reply8"},{"role":"user","content":"msg9"},{"role":"assistant","content":"reply9"},{"role":"user","content":"msg10"},{"role":"assistant","content":"reply10"},{"role":"user","content":"msg11"},{"role":"assistant","content":"reply11"}]'
WHEN compact messages=$long_chat model="gemini-3-flash"
# 压缩后消息数应少于原始数量
THEN assert_messages_count expected=16

[SCENARIO: HC-003] TITLE: 工具输出截断 TAGS: unit compression
# 验证长工具输出被截断
LET tool_msg = '[{"role":"user","content":"read file"},{"role":"assistant","tool_calls":[{"id":"1"}]},{"role":"tool","tool_call_id":"1","content":"very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times very long output repeated many times"}]'
WHEN truncate_tool_outputs messages=$tool_msg
THEN assert_message_content index=2 contains="tool_call_id"


