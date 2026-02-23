[SCENARIO: DB-OWN-001] TITLE: Mix test command is permitted for DB ownership verification
  GIVEN signal_bus_is_clean
  WHEN check_shell_command command="mix test test/jido_studio/agents/llm_agent_test.exs"
  THEN assert_approval_required required=false
