# ReadStructure Parser Split Analysis (2026-02-21)

## Goal
Split language-specific structure extraction out of `read_structure.ex` so new language support does not expand the handler module, while keeping the public behavior unchanged.

## Current State
`lib/cortex/tools/handlers/read_structure.ex` contains all language extraction logic:
- Elixir AST + fallback
- JS/TS regex
- Rust regex
- Python regex
- Go regex
- Unsupported fallback preview

## Desired State
Keep `ReadStructure` as the entry point and route to dedicated parser modules under `lib/cortex/tools/handlers/read_structure/`.

## Constraints
- Public API and outputs must remain identical.
- No circular dependencies.
- Keep extraction logic functionally unchanged; only move code.

## BDD Notes
The current BDD instruction set does not contain domain-specific steps for `read_structure`. No direct DSL scenario exists to assert the structure output without adding new instructions. The refactor proceeds without new BDD coverage and should be revisited if BDD instructions are extended.
