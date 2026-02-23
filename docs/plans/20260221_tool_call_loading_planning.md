# Tool Call Loading State Plan (2026-02-21)

## Scope
Add a visible loading indicator in the chat UI while tool calls are running, based on tool call request/result signals.

## Architecture Notes
- Signals are the cross-boundary contract. UI state must derive from SignalHub events.
- Use existing `tool.call.request` and `tool.call.result` events to track pending tool calls.
- UI should render a lightweight indicator in the streaming area.

## Task DAG (taskctl)
L0: Add UI loading state for tool calls
L1: Define BDD scenario for tool call loading
L2: Verify tool call loading flow

## BDD-Driven Iteration
- DSL will be added under `test/bdd/dsl/`.
- Use `signal_is_emitted` + `assert_signal_data` to validate signal payload shape.
- Compile BDD after changes; run gates if requested.

## Implementation Plan
1. Track pending tool calls in LiveView assigns.
2. Increment on `tool.call.request`, decrement on `tool.call.result`.
3. Render a loader component when count > 0.
4. Add BDD DSL scenario for signal payload shape.
5. Compile BDD (and run gates if desired).
