# BDD Instruction + Signal Format Fixes Analysis

Date: 2026-02-20

## Scope
- Address missing BDD instructions mentioned in the failure analysis.
- Resolve signal format mismatches in BDD DSL where type naming was nonstandard.
- Harden history flush behavior to avoid crashes when SignalRecorder is not running.

## Findings
- `Cortex.BDD.Instructions.V1` already implements `send_chat_message`, `history_file_should_contain`, and `assert_tool_result`, but lacks `emit_signal` and `assert_signal_emitted`.
- History flush logic in `history_file_should_contain` and `history_file_should_not_contain` assumes `SignalRecorder` exists, which can raise `ArgumentError` when it is not started.
- `test/bdd/dsl/signal_hub_core.dsl` used types `test.event` and `chat.message`, which do not follow the current standard catalog (and can conflict with V3 naming expectations).

## Decisions
- Add `emit_signal` and `assert_signal_emitted` to both runtime and instruction spec.
- Implement a safe `flush_signal_recorder/1` helper and use it where history flushing is needed.
- Update `signal_hub_core.dsl` to use `test.event.emit` and `agent.chat.request`.

## Expected Impact
- Removes missing-instruction failures tied to `emit_signal` and `assert_signal_emitted`.
- Eliminates crashes from flushing a missing `SignalRecorder` process.
- Aligns core DSL scenarios with V3-style signal type naming.
