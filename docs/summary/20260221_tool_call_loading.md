# Summary: Tool Call Loading State (2026-02-21)

## What changed
- Added UI loading indicator during tool execution by tracking pending tool calls.
- Hooked SignalHub tool call request/result events into LiveView state.
- Added BDD DSL scenario for tool.call.request payload shape.

## Files touched
- lib/cortex_web/live/helpers/agent_live_helpers.ex
- lib/cortex_web/live/helpers/signal_dispatcher.ex
- lib/cortex_web/live/jido_live.ex
- lib/cortex_web/live/components/jido_components/chat_panel.ex
- test/bdd/dsl/tool_call_loading.dsl
- docs/analysis/20260221_tool_call_loading.md
- docs/plans/20260221_tool_call_loading_planning.md
- docs/progress/20260221_tool_call_loading.md
- docs/summary/20260221_tool_call_loading.md

## Tests
- Not run in this pass. Suggested: `bddc compile` and `./scripts/bdd_gate.sh`.
