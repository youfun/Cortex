# Analysis: Tool Call Loading State (2026-02-21)

## Problem
Tool calling has no visible loading state in the chat UI. Users perceive the system as stuck while tools run (e.g., `mix phx.new` waiting for input).

## Root Cause
The UI only shows `is_thinking` while the LLM is generating. Once tool execution begins, there is no distinct UI feedback tied to tool lifecycle signals.

## Approach
- Track pending tool calls via SignalHub events:
  - Increment on `tool.call.request`.
  - Decrement on `tool.call.result`.
- Render a lightweight “Tools running...” indicator when pending count > 0.
- Keep state scoped to the active session.

## Risks
- Missed decrements if signals are not emitted or if tool results are dropped.
- Multiple tool calls require correct counting, not just a boolean.

## Mitigations
- Clamp count to >= 0.
- Reset count on `agent.turn.end` / `agent.run.end`.
