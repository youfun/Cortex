[SCENARIO: MEMORY-P1-001] TITLE: BackgroundChecks 运行并返回结构 TAGS: memory background_checks
  GIVEN start_agent
  WHEN execute_tool tool_name="run_memory_checks" args='{}'
  THEN assert_tool_result contains="actions"
  THEN assert_tool_result contains="warnings"
  THEN assert_tool_result contains="suggestions"

[SCENARIO: MEMORY-P1-002] TITLE: DetectInsights 运行并返回结构 TAGS: memory insight_detector
  GIVEN start_agent
  WHEN execute_tool tool_name="detect_insights" args='{}'
  THEN assert_tool_result contains="status"
