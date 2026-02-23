[SCENARIO: FILE-READ-001] TITLE: Read existing file
  GIVEN start_agent
  
  # Setup file first
  WHEN execute_tool tool_name="write_file" args='{"path":"to_read.txt","content":"readable content"}'
  
  WHEN execute_tool tool_name="read_file" args='{"path":"to_read.txt"}'
  THEN assert_tool_result contains="readable content"

[SCENARIO: FILE-READ-002] TITLE: Read non-existent file
  GIVEN start_agent
  
  WHEN execute_tool tool_name="read_file" args='{"path":"non_existent.txt"}'
  THEN assert_tool_result contains="error"
  THEN assert_tool_result contains="File not found"

[SCENARIO: FILE-READ-003] TITLE: Path traversal read denied
  GIVEN start_agent
  
  WHEN execute_tool tool_name="read_file" args='{"path":"../secret.txt"}'
  THEN assert_tool_result contains="error"
  THEN assert_tool_result contains="permission"
