# Memory System Phase 1 BDD Tests

[SCENARIO: MEMORY-P0-002] TITLE: 提议 Evidence 字段支持 TAGS: memory proposal evidence
GIVEN start_agent
WHEN execute_tool tool_name="create_proposal" args='{"content":"evidence_test","evidence":["source_a","source_b"]}'
THEN assert_tool_result contains="evidence"
THEN assert_tool_result contains="source_a"
