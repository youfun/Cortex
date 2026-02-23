# Let It Crash Fixes Summary

Date: 2026-02-21

## Overview
Refactored `lib/` to remove defensive `try/rescue/catch` usage that masked failures, aligning with the style guide’s “Let it Crash” principle.

## Key Changes
- Removed catch-all error handling around runner execution, IEx tool evaluation, LLM client calls, and shell command port setup.
- Simplified configuration loading to rely on return-value APIs instead of exceptions.
- Stopped swallowing errors during signal emission across memory subsystems.
- Replaced unsafe `String.to_existing_atom/1` rescue patterns with `SafeAtom` helpers where applicable.

## Remaining Exceptions (Intentional)
- Narrow rescues for specific, expected errors (e.g., sandbox checkout, DB connection errors, safe atom conversion).

## Files Touched (Highlights)
- `lib/cortex/runners/fan_out.ex`
- `lib/cortex/runners/cli.ex`
- `lib/cortex/tools/handlers/iex_console.ex`
- `lib/cortex/llm/client.ex`
- `lib/cortex/memory/*`
- `lib/cortex/channels/*`
- `lib/cortex/shell/commands/system_exec.ex`
- `lib/cortex/session/coordinator.ex`
- `lib/cortex/application.ex`
