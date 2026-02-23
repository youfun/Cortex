[SCENARIO: TOOL-LOAD-001] TITLE: tool.call.request carries tool name TAGS: tool signal payload
GIVEN signal_bus_is_clean
WHEN signal_is_emitted type="tool.call.request" data='{"tool":"shell","call_id":"call_tool_load","params":{"command":"echo tool_load"},"session_id":"tool_load"}' session_id="tool_load"
THEN assert_signal_data type="tool.call.request" path="payload.tool" expected="shell"
