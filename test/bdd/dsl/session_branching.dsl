[SCENARIO: SESS-BRANCH-001] TITLE: Create Branch
  GIVEN signal_bus_is_clean
  GIVEN start_agent session_id="main_branch"
  
  WHEN create_session_branch parent_session_id="main_branch" purpose="unit_testing" branch_id="branch_1"
  
  THEN history_file_should_contain type="session.branch.created"
  THEN assert_signal_data type="session.branch.created" path="payload.branch_session_id" expected="branch_1"

[SCENARIO: SESS-BRANCH-002] TITLE: Complete Branch
  LET res = '{"summary":"done"}'
  WHEN complete_session_branch branch_session_id="branch_1" result=$res
  
  THEN history_file_should_contain type="session.branch.completed"

[SCENARIO: SESS-BRANCH-003] TITLE: Merge Branch
  WHEN merge_session_branch branch_session_id="branch_1" target_session_id="main_branch" strategy="append"
  
  THEN history_file_should_contain type="session.branch.merged"
