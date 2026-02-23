# ReadStructure Parser Unit Tests Analysis (2026-02-21)

## Goal
Add focused unit tests for the pure parser modules under `read_structure/`.

## Scope
Directly test each parser module's `extract/1` (or `extract/2` for fallback) to validate output formatting and basic behavior without file IO.

## BDD Note
The current BDD instruction set lacks steps for `read_structure` parsing. Unit tests are added directly in ExUnit. If BDD steps are added later, these scenarios can be mirrored in DSL.
