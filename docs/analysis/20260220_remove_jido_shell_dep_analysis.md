# Remove jido_shell Dependency - Analysis

Date: 2026-02-20

## Context
The dependency chain `jido_shell -> hako (jido_vfs) -> splode` breaks under the current Elixir toolchain. The codebase only uses two `jido_shell` pieces inside `lib/cortex/shell/commands/system_exec.ex`:

- `@behaviour Jido.Shell.Command`
- `Jido.Shell.Error` for constructing errors

The core execution path already uses `Sandbox.execute` and does not depend on `jido_shell`.

## Decision
Replace the minimal behaviour and error struct locally under `Cortex.Shell` and remove the `:jido_shell` dependency. Keep runtime behavior unchanged.

## Scope
- Add `Cortex.Shell.Command` behaviour.
- Add `Cortex.Shell.Error` struct with `shell/2` and `command/2` helpers.
- Update `system_exec.ex` to reference the new modules.
- Remove `:jido_shell` from `mix.exs` and clean related lock entries.

## Verification
Compile and boot should succeed after dependency removal:

- `mix compile --warnings-as-errors`
- `mix phx.server`
