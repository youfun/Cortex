[SCENARIO: FILE-EDIT-001] TITLE: Edit file in sandbox
  GIVEN start_agent
  
  LET content = "Hello world"
  # Assuming edit_file or write_file tool exists
  WHEN execute_tool tool_name="write_file" args='{"path":"test_edit.txt","content":"Hello world"}'
  THEN assert_tool_result contains="Successfully wrote"
  
  # Read back to verify? Or just trust result.
  # Assuming read_file tool exists
  WHEN execute_tool tool_name="read_file" args='{"path":"test_edit.txt"}'
  THEN assert_tool_result contains="Hello world"

[SCENARIO: FILE-EDIT-002] TITLE: Path traversal denied
  GIVEN start_agent
  
  WHEN execute_tool tool_name="write_file" args='{"path":"../outside.txt","content":"hack"}'
  # Expect failure
  THEN assert_tool_result contains="error"
  THEN assert_tool_result contains="permission"

[SCENARIO: FILE-EDIT-003] TITLE: String keys support
  GIVEN start_agent
  
  # Using string keys in JSON args which happens by default in BDD
  WHEN execute_tool tool_name="write_file" args='{"path":"string_keys.txt","content":"works"}'
  THEN assert_tool_result contains="Successfully wrote"
