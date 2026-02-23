# BDD Instructions V1 Split

[SCENARIO: BDD-V1-SPLIT-001] TITLE: Route steps across split modules TAGS: bdd v1 split
GIVEN signal_bus_is_clean
WHEN emit_signal type="agent.chat.request" data='{"content":"hello","session_id":"bdd_split_session"}'
THEN assert_signal_emitted type="agent.chat.request" session_id="bdd_split_session"
WHEN register_dynamic_tool tool_name="bdd_split_tool" description="Split routing tool"
THEN assert_tool_available tool_name="bdd_split_tool"
WHEN unregister_dynamic_tool tool_name="bdd_split_tool"
THEN assert_tool_not_available tool_name="bdd_split_tool"
WHEN truncate_head content_var="some_text" max_lines=1
THEN assert_truncation_result truncated=true
WHEN check_shell_command command="rm -rf /tmp/does_not_matter"
THEN assert_approval_required required=true
