---
name: mix-master
description: Manage Elixir dependencies at runtime using Mix
---

# MixMaster Skill

You can manage Elixir project dependencies using this skill.

## Adding a dependency

When you need to add a new Elixir package to the project:

1. **Read** the current `mix.exs` file to understand the existing dependencies
2. **Edit** `mix.exs` to add the dependency to the `deps()` function:
   ```elixir
   defp deps do
     [
       {:new_package, "~> 1.0"}
       # ... other deps
     ]
   end
   ```
3. Run `shell` tool with command: `mix deps.get` to fetch the new dependency
4. Run `shell` tool with command: `mix compile` to compile and verify

## Common Mix commands

### Dependency management
- `mix deps.get` - Fetch dependencies
- `mix deps.update package_name` - Update a specific package
- `mix deps.clean --all` - Clean all dependencies (use carefully)
- `mix deps.tree` - Show dependency tree

### Project operations
- `mix compile` - Compile the project
- `mix compile --warnings-as-errors` - Compile with strict mode
- `mix clean` - Clean build artifacts

### Testing
- `mix test` - Run all tests
- `mix test test/path/to/file_test.exs` - Run specific test file
- `mix test test/path/to/file_test.exs:42` - Run test at specific line
- `mix test --failed` - Re-run only failed tests

### Code quality
- `mix format` - Format code according to .formatter.exs
- `mix format --check-formatted` - Check if code is formatted
- `mix credo` - Run static code analysis (if credo is installed)

### Phoenix specific
- `mix phx.routes` - List all Phoenix routes
- `mix phx.server` - Start Phoenix server
- `mix phx.gen.context` - Generate context
- `mix phx.gen.live` - Generate LiveView

### Database (Ecto)
- `mix ecto.create` - Create database
- `mix ecto.migrate` - Run migrations
- `mix ecto.rollback` - Rollback last migration
- `mix ecto.reset` - Drop, create, migrate, and seed database

## Best practices

1. **Always read mix.exs first** before adding dependencies to avoid duplicates
2. **Check compilation** after adding new dependencies
3. **Run tests** to ensure new dependencies don't break existing code
4. **Format code** after making changes with `mix format`
5. **Update documentation** if you add a significant dependency

## Example workflow

```elixir
# User asks: "Add the Jason library for JSON parsing"

# Step 1: Read current mix.exs
read_file("mix.exs")

# Step 2: Edit to add Jason
edit_file(
  path: "mix.exs",
  old_string: "defp deps do\n    [",
  new_string: "defp deps do\n    [\n      {:jason, \"~> 1.4\"},"
)

# Step 3: Fetch dependency
shell("mix deps.get")

# Step 4: Compile to verify
shell("mix compile")
```
