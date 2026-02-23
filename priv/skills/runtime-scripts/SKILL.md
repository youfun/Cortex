---
name: runtime-scripts
description: Use Mix.install to execute standalone Elixir scripts with dynamic dependencies for tasks, tests, and API logic
---

# Runtime Scripts Skill (Mix.install)

This skill enables you to create and execute self-contained Elixir scripts. This is the preferred way to run temporary logic, test new libraries, or perform one-off data migrations without modifying the main project's `mix.exs`.

## Core Concept

Use `Mix.install/2` at the top of an `.exs` file to manage dependencies.

### Generic Task Template

```elixir
Mix.install([
  {:jason, "~> 1.4"},
  {:req, "~> 0.5"}
])

defmodule TaskRunner do
  def run do
    # Perform complex logic here
    IO.puts("Script executed successfully.")
  end
end

TaskRunner.run()
```

## Best Practices

1. **Isolation**: Use scripts for code that shouldn't persist in the main codebase.
2. **Local References**: You can reference the host project: `{:cortex, path: "."}`.
3. **Execution**: Use the `shell` tool: `elixir my_script.exs`.
4. **UI Prototyping**: If you need to build a web-based UI or LiveView demo, **DO NOT** use this skill alone. Instead, refer to the **`phoenix-playground`** skill for detailed instructions on ports, styling, and LiveView structure.