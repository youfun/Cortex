# Sandbox Logic BDD Test
# Verifies that path traversal is blocked by the underlying security module.

[SCENARIO: SANDBOX-001] TITLE: Block path traversal in write_file TAGS: unit security
LET args = '{"path":"../hacker.txt", "content":"pwned"}'
WHEN execute_tool tool_name="write_file" args=$args
THEN assert_tool_result contains="permission_denied"
