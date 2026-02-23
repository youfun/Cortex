# Truncate BDD 测试
# 验证工具输出截断逻辑

[SCENARIO: TRUNCATE-001] TITLE: 基础行截断 (head) TAGS: unit truncate
LET raw_text = "line1 line2 line3"
WHEN truncate_head content_var=$raw_text max_lines=2
THEN assert_truncation_result truncated=false

[SCENARIO: TRUNCATE-TOOL-001] TITLE: ToolRunner 自动截断 (read_file) TAGS: integration truncate
# 准备一个长文件
GIVEN shell command="seq 1 1200 > bdd_long_test.txt"
WHEN execute_tool tool_name="read_file" args='{"path":"bdd_long_test.txt"}'
THEN assert_tool_result contains="1" truncated=true
GIVEN shell command="rm bdd_long_test.txt"

[SCENARIO: TRUNCATE-TOOL-002] TITLE: ToolRunner 尾部截断 (tail) TAGS: integration truncate
# 使用 shell 工具产生大量输出
WHEN execute_tool tool_name="shell" args='{"command":"seq 1 1200"}'
THEN assert_tool_result contains="1200" truncated=true
