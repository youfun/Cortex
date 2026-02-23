# Progress: Tool Call Loading State (2026-02-21)

- Added pending tool call count tracking in LiveView assigns.
- Wired SignalDispatcher to increment/decrement on tool call request/result.
- Rendered a “Tools running...” indicator in chat streaming area.
- Added BDD DSL scenario to validate tool.call.request payload.

Pending:
- Compile BDD (bddc) and run gates if needed.
