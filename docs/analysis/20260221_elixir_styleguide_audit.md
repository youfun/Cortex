# Elixir Style Guide Audit (2026-02-21)

## Scope
- Codebase: `/home/Debian13/code/cortex`
- Reference: `.github/Guidelines/ElixirStyleGuide.md`
- Files scanned: `lib/**/*.ex`, `lib/**/*.exs`, `test/**/*.exs`, `skill/**/*.exs` (excluding `deps` and `_build`).

## Method
- Focused on high-signal anti-patterns explicitly called out in the style guide: unsafe atom creation, list append in loops, pipeline into control flow, and debug IO.
- Used `rg` to locate candidate patterns, then reviewed surrounding context.

## Findings

### 1) Unsafe `String.to_atom/1` on dynamic input (Security Red Line)
Rule: **绝对禁止**对用户输入使用 `String.to_atom/1`（DoS risk, atom exhaustion).

Occurrences with risk:
- `lib/cortex_web/live/settings_live/channels.ex:22` uses `String.to_atom(tab)` where `tab` comes from LiveView params.
- `lib/cortex/bdd/instructions/v1.ex:983,985,1118,1239` converts `args` and `var_name` to atoms from external data.
- `lib/cortex/channels/channels.ex:56-66` converts config keys to atoms, falling back to `String.to_atom/1` on unknown keys.
- `lib/cortex/channels/config_loader.ex:33` converts `adapter` to atom for `Application.get_env/3`.
- `lib/cortex/channels/channels.ex:73` `String.to_atom/1` on dynamic keys (from config load).

Notes:
- `test/support/credo/checks/security/unsafe_atom_conversion.ex` intentionally uses `String.to_atom/1` as a test target; this is OK for tests.

Recommended fixes:
- Use a whitelist mapping (`case`/`Map.fetch!`) for known values.
- Use `String.to_existing_atom/1` where possible, and return error on unknown keys.
- Store keys as strings rather than atoms for config maps unless strictly bounded.

### 2) List append `list ++ [item]` in hot paths (Performance Pitfall)
Rule: **禁止**在循环或累积中使用 `list ++ [new]` (O(n) append).

Occurrences:
- `lib/cortex_web/live/helpers/permission_helpers.ex:21` queue append.
- `lib/cortex/extensions/hook_registry.ex:44,51` appending to hooks lists.
- `lib/cortex/actions/ai/route_chat.ex:207` append in message build.
- `lib/cortex/tools/handlers/read_structure.ex:130-160` repeated `acc ++ [...]` in `Macro.prewalk`.
- `lib/cortex/extensions/examples/git_extension.ex:131` appending file arg.
- `lib/cortex/agents/compaction.ex:145,156,255` repeated appends while reducing.
- `lib/cortex/agents/steering.ex:25` queue append.
- `lib/cortex/memory/background_checks.ex:61-101` warnings/suggestions append.
- `lib/cortex/agents/actions/coding/implementation_result_action.ex:60` errors append.
- `lib/cortex/agents/actions/coding/review_result_action.ex:40,103` errors/history append.

Recommended fixes:
- Prepend with `[item | list]` and `Enum.reverse/1` when order matters.
- Use `:queue` or `MapSet` for queues or uniqueness (e.g., hooks).
- For accumulators in traversals (`read_structure.ex`), build reversed lists and reverse once at end.

### 3) Pipeline into control flow (`|> case/if/with`)
Rule: **严禁**将管道结果直接送入 `case`, `if`, or `with`.

Occurrences:
- `lib/cortex/agents/token_counter.ex:47-52`
- `lib/cortex/memory/context_builder.ex:106-114`
- `lib/cortex/tts/router.ex:14-20`
- `lib/cortex/memory/token_budget.ex:257-262`

Recommended fixes:
- Assign to a variable, then run `case`/`if` on the variable:
  - `value = ...; case value do ... end`

### 4) Broad `try/rescue` for flow control
Rule: “不要试图用 `try/rescue` 捕获所有错误.”

Occurrence:
- `lib/cortex/tools/handlers/read_structure.ex:112-121` uses `try/rescue` to fall back to regex parsing.

Notes:
- This may be acceptable as a parse-fallback, but it’s still a full catch-all. Consider narrowing to specific errors or replacing with `Code.string_to_quoted/2` pattern matching on `{:ok, ast}` / `{:error, ...}`.

### 5) Debug IO in non-test code
Rule: **严禁**保留 `IO.inspect` in production code.

Occurrence:
- `skill/playground.exs:532` uses `IO.inspect`. This is a skill playground, but still violates the guideline if treated as production.

Recommended fixes:
- Replace with `dbg/2` or remove for committed non-test code.

## Summary
Highest risk items are unsafe `String.to_atom/1` on dynamic inputs and list append in loops. These are explicitly prohibited in the style guide and can lead to production risks (DoS) and performance regressions. Pipeline-into-control-flow occurrences are style violations that reduce readability and diff clarity.

## Gaps / Not Covered
- No exhaustive audit of module layout ordering (`use/import/alias/require`) or docs+doctest coverage.
- No runtime tests executed.

