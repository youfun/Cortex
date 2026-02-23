[SCENARIO: MEMORY-FLOW-001] TITLE: WorkingMemory receives focus from user input signal TAGS: memory working_memory hook
  GIVEN signal_bus_is_clean
  GIVEN start_agent
  # Simulate user chat request which should trigger MemoryHook.on_input -> WorkingMemory.set_focus
  WHEN signal_is_emitted type="agent.chat.request" data='{"content": "帮我用 Phoenix 写一个 REST API"}' session_id="mem_test"
  # WorkingMemory should now have a focus set
  THEN assert_working_memory_has_focus contains="Phoenix"

[SCENARIO: MEMORY-FLOW-002] TITLE: Subconscious extracts coding context from user input TAGS: memory subconscious coding
  GIVEN signal_bus_is_clean
  # Analyze content with coding-specific patterns
  WHEN subconscious_analyze content="我们项目用Elixir框架，代码风格遵循 Credo strict"
  THEN assert_proposals_created min_count=1
  THEN assert_proposal_content contains="Elixir"

[SCENARIO: MEMORY-FLOW-003] TITLE: Subconscious extracts technology stack TAGS: memory subconscious tech
  GIVEN signal_bus_is_clean
  WHEN subconscious_analyze content="We are building with React and TypeScript using Next.js"
  THEN assert_proposals_created min_count=1
  THEN assert_proposal_content contains="React"

[SCENARIO: MEMORY-FLOW-004] TITLE: Subconscious extracts project conventions TAGS: memory subconscious conventions
  GIVEN signal_bus_is_clean
  WHEN subconscious_analyze content="Check the mix.exs for dependencies, run mix test with ExUnit"
  THEN assert_proposals_created min_count=1
  THEN assert_proposal_content contains="Elixir/Mix"

[SCENARIO: MEMORY-FLOW-005] TITLE: Auto-accept proposals with lowered threshold TAGS: memory proposal auto_accept
  GIVEN signal_bus_is_clean
  # A proposal with confidence 0.70 from safe source should now be auto-accepted
  WHEN memory_proposal_created confidence=0.70 source_actor="user" source_signal_type="agent.chat.request"
  THEN assert_proposal_auto_accepted

[SCENARIO: MEMORY-FLOW-006] TITLE: Reject proposals from unsafe sources TAGS: memory proposal security
  GIVEN signal_bus_is_clean
  # A proposal from non-user source should not be auto-accepted even with high confidence
  WHEN memory_proposal_created confidence=0.90 source_actor="unknown" source_signal_type="webhook.incoming"
  THEN assert_proposal_not_auto_accepted
