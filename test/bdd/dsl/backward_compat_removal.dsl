# Backward compat removal and logic optimization

[SCENARIO: BACKWARD-COMPAT-001] TITLE: Standard signal is recorded TAGS: signals history
GIVEN signal_bus_is_clean
WHEN signal_is_emitted type="agent.response" data='{"content":"ok","session_id":"bc_session"}' session_id="bc_session"
THEN history_file_should_contain type="agent.response"

[SCENARIO: BACKWARD-COMPAT-002] TITLE: Noise signal is filtered from history TAGS: signals history noise
GIVEN signal_bus_is_clean
WHEN signal_is_emitted type="agent.response.chunk" data='{"delta":"hi","session_id":"bc_session"}' session_id="bc_session"
THEN history_file_should_not_contain type="agent.response.chunk"
