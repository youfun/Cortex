[SCENARIO: PERM-REQ-001] TITLE: permission.request carries command reason tool TAGS: permission signal payload
GIVEN signal_bus_is_clean
WHEN signal_is_emitted type="permission.request" data='{"request_id":"req_cmd","command":"rm -rf /","reason":"permission_required","tool":"shell","session_id":"perm_payload"}' session_id="perm_payload"
THEN assert_signal_data type="permission.request" path="payload.command" expected="rm -rf /"
THEN assert_signal_data type="permission.request" path="payload.reason" expected="permission_required"
THEN assert_signal_data type="permission.request" path="payload.tool" expected="shell"
