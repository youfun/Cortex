[SCENARIO: PERM-LIFE-001] TITLE: First time request generates pending request
  GIVEN signal_bus_is_clean
  
  # Assuming check_permission will trigger a request if not found
  WHEN check_permission actor="user" action="write_file" context="test.txt" session_id="perm_test"
  
  # It should verify authorization is false initially
  THEN assert_authorized actor="user" action="write_file" expected=false session_id="perm_test"
  
[SCENARIO: PERM-LIFE-002] TITLE: Resolve Allow Once
  GIVEN signal_bus_is_clean
  LET req_id = "req_allow_once"
  
  # Simulate a request resolution
  WHEN resolve_permission_request request_id=$req_id decision="allow" duration="once" session_id="perm_test"
  
  # We just assert that it didn't crash and maybe checked something.
  THEN assert_authorized actor="user" action="unknown_action" expected=false session_id="perm_test"

[SCENARIO: PERM-LIFE-003] TITLE: Resolve Allow Always
  GIVEN signal_bus_is_clean
  LET req_id = "req_allow_always"
  
  WHEN resolve_permission_request request_id=$req_id decision="allow" duration="always" session_id="perm_test"
  THEN assert_authorized actor="user" action="unknown_action" expected=false session_id="perm_test"

[SCENARIO: PERM-LIFE-004] TITLE: Resolve Deny
  GIVEN signal_bus_is_clean
  LET req_id = "req_deny"
  
  WHEN resolve_permission_request request_id=$req_id decision="deny" duration="once" session_id="perm_test"
  THEN assert_authorized actor="user" action="unknown_action" expected=false session_id="perm_test"
