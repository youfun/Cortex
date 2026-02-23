# Extension Lifecycle Management

[SCENARIO: EXT-LIFECYCLE-001] TITLE: HookRegistry starts and manages hooks TAGS: extension registry
GIVEN signal_bus_is_clean
GIVEN start_agent session_id="ext_registry_session"
THEN history_file_should_contain type="agent.turn.start"

[SCENARIO: EXT-LIFECYCLE-002] TITLE: on_input Hook processes user input TAGS: extension hook input
GIVEN signal_bus_is_clean
GIVEN start_agent session_id="ext_input_session"
WHEN signal_is_emitted type="agent.chat.request" data='{"session_id":"ext_input_session","content":"test message"}' session_id="ext_input_session"
THEN history_file_should_contain type="agent.chat.request"

[SCENARIO: EXT-LIFECYCLE-003] TITLE: Context hooks can modify messages TAGS: extension hook context
GIVEN signal_bus_is_clean
GIVEN start_agent session_id="ext_context_session"
WHEN signal_is_emitted type="context.build.start" data='{"session_id":"ext_context_session","turn_id":"turn_1"}' session_id="ext_context_session"
THEN history_file_should_contain type="context.build.start"

[SCENARIO: EXT-LIFECYCLE-004] TITLE: Tool result hooks can process outputs TAGS: extension hook tool
GIVEN signal_bus_is_clean
WHEN execute_tool tool_name="read_file" args='{"path":"test.txt"}'
THEN assert_tool_result contains="test"

[SCENARIO: EXT-LIFECYCLE-005] TITLE: Session lifecycle signals are recorded TAGS: extension signals session
GIVEN signal_bus_is_clean
GIVEN start_agent session_id="lifecycle_session"
THEN history_file_should_contain type="agent.turn.start"
WHEN restart_agent session_id="lifecycle_session"
THEN history_file_should_contain type="agent.turn.end"

# S4-S6 New Scenarios

[SCENARIO: EXT-LIFECYCLE-006] TITLE: on_agent_end Hook is called when turn completes TAGS: extension hook agent_end s4
GIVEN signal_bus_is_clean
GIVEN start_agent session_id="test_agent_end"
WHEN send_chat_message session_id="test_agent_end" content="Hello, respond without tools"
THEN wait_for_turn_complete session_id="test_agent_end"
THEN history_file_should_contain type="agent.turn.end"

[SCENARIO: EXT-LIFECYCLE-007] TITLE: on_before_agent Hook can temporarily modify system_prompt TAGS: extension hook before_agent s5
GIVEN signal_bus_is_clean
GIVEN start_agent session_id="test_system_prompt"
WHEN send_chat_message session_id="test_system_prompt" content="What is your role?"
THEN wait_for_turn_complete session_id="test_system_prompt"
THEN history_file_should_contain type="agent.response"

[SCENARIO: EXT-LIFECYCLE-008] TITLE: on_compaction_before Hook can cancel compaction TAGS: extension hook compaction s6
GIVEN signal_bus_is_clean
GIVEN start_agent session_id="test_compaction"
WHEN send_chat_message session_id="test_compaction" content="Fill context with long message"
THEN wait_for_turn_complete session_id="test_compaction"
THEN history_file_should_contain type="agent.response"

