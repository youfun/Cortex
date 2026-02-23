# Summary (2026-02-21)

Completed the parser split for `ReadStructure` by moving language-specific extraction into dedicated modules and routing in the handler. Behavior and outputs remain unchanged.

## Files Added
- lib/cortex/tools/handlers/read_structure/elixir_parser.ex
- lib/cortex/tools/handlers/read_structure/js_parser.ex
- lib/cortex/tools/handlers/read_structure/rust_parser.ex
- lib/cortex/tools/handlers/read_structure/python_parser.ex
- lib/cortex/tools/handlers/read_structure/go_parser.ex
- lib/cortex/tools/handlers/read_structure/fallback_parser.ex

## Files Updated
- lib/cortex/tools/handlers/read_structure.ex
