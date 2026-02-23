# Signal-first event catalog adoption

[SCENARIO: SIGNAL-FIRST-001] TITLE: Session lifecycle emits start and shutdown TAGS: signals lifecycle
GIVEN signal_bus_is_clean
GIVEN start_agent session_id="signal_first_session"
THEN history_file_should_contain type="session.start"
WHEN restart_agent session_id="signal_first_session"
THEN history_file_should_contain type="session.shutdown"

[SCENARIO: SIGNAL-FIRST-002] TITLE: Context build signals are recorded TAGS: signals context
GIVEN signal_bus_is_clean
WHEN signal_is_emitted type="context.input.transform" data='{"original_text":"hello","transformed_text":"hello!","session_id":"ctx_session"}' session_id="ctx_session"
WHEN signal_is_emitted type="context.build.start" data='{"turn_id":"turn_1","session_id":"ctx_session"}' session_id="ctx_session"
WHEN signal_is_emitted type="context.build.result" data='{"turn_id":"turn_1","message_count":2,"session_id":"ctx_session"}' session_id="ctx_session"
THEN history_file_should_contain type="context.input.transform"
THEN history_file_should_contain type="context.build.start"
THEN history_file_should_contain type="context.build.result"

[SCENARIO: SIGNAL-FIRST-003] TITLE: Tool call and permission flow signals are recorded TAGS: signals tool permission
GIVEN signal_bus_is_clean
WHEN signal_is_emitted type="tool.call.request" data='{"tool":"write_file","call_id":"call_1","session_id":"tool_session"}' session_id="tool_session"
WHEN signal_is_emitted type="tool.call.blocked" data='{"tool":"write_file","reason":"permission_required","session_id":"tool_session"}' session_id="tool_session"
WHEN signal_is_emitted type="permission.request" data='{"request_id":"req_1","session_id":"tool_session"}' session_id="tool_session"
WHEN signal_is_emitted type="permission.resolved" data='{"request_id":"req_1","approved":true,"session_id":"tool_session"}' session_id="tool_session"
WHEN signal_is_emitted type="tool.call.result" data='{"tool":"write_file","call_id":"call_1","result":"ok","session_id":"tool_session"}' session_id="tool_session"
THEN history_file_should_contain type="tool.call.request"
THEN history_file_should_contain type="tool.call.blocked"
THEN history_file_should_contain type="permission.request"
THEN history_file_should_contain type="permission.resolved"
THEN history_file_should_contain type="tool.call.result"
