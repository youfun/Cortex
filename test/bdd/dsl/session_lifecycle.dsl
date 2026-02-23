[SCENARIO: SESS-LIFE-001] TITLE: Ensure Session starts agent
  GIVEN signal_bus_is_clean
  GIVEN start_agent session_id="life_cycle_test"
  
  THEN history_file_should_contain type="session.start"
  
[SCENARIO: SESS-LIFE-002] TITLE: Stop Session stops agent
  GIVEN start_agent session_id="life_cycle_test"
  WHEN stop_session session_id="life_cycle_test"
  
  THEN history_file_should_contain type="session.shutdown"
  
[SCENARIO: SESS-LIFE-003] TITLE: Switch Session
  GIVEN start_agent session_id="old_session"
  
  LET opts = '{"model":"gpt-4"}'
  WHEN switch_session old_session_id="old_session" new_session_id="new_session" opts=$opts
  
  # New session should start
  THEN history_file_should_contain type="session.start"
  # Old session should be scheduled for stop (async), so we might not see immediate stop signal
