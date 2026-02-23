---
name: playground
description: Quick code experimentation using IEx tool
---

# Playground Skill

Use the `iex` tool for quick experimentation and debugging Elixir code.

## Why use IEx tool?

The IEx tool provides a **persistent** Elixir session where you can:
- Test functions without writing files
- Experiment with data transformations
- Debug complex expressions
- Validate code before implementing it

Each session maintains state across tool calls, so variables persist.

## Usage patterns

### Test a function
```elixir
iex("MyModule.my_function(arg1, arg2)")
```

### Inspect data structures
```elixir
iex("data = %{key: \"value\", nested: %{a: 1}}")
iex("Map.keys(data)")  # Variables persist across calls
```

### Debug with IO.inspect
```elixir
iex("[1, 2, 3] |> Enum.map(&(&1 * 2)) |> IO.inspect(label: \"doubled\")")
```

### Test pipes
```elixir
iex("""
[1, 2, 3, 4, 5]
|> Enum.filter(&rem(&1, 2) == 0)
|> Enum.map(&(&1 * 2))
|> Enum.sum()
""")
```

### Validate regex
```elixir
iex("Regex.match?(~r/[0-9]+/, \"abc123\")")
```

### Check module functions
```elixir
iex("MyModule.__info__(:functions)")
```

## Common Elixir patterns to test

### Pattern matching
```elixir
iex("{:ok, value} = {:ok, 42}")
iex("value")  # => 42
```

### List operations
```elixir
iex("list = [1, 2, 3]")
iex("[head | tail] = list")
iex("head")  # => 1
iex("tail")  # => [2, 3]
```

### Map operations
```elixir
iex("map = %{a: 1, b: 2}")
iex("Map.put(map, :c, 3)")
iex("Map.get(map, :a)")
iex("map.a")  # Access syntax
```

### Enum operations
```elixir
iex("Enum.reduce([1, 2, 3], 0, &+/2)")
iex("Enum.zip([1, 2], [:a, :b])")
iex("Enum.group_by([\"apple\", \"apricot\", \"banana\"], &String.first/1)")
```

### String operations
```elixir
iex("String.split(\"hello world\", \" \")")
iex("String.upcase(\"hello\")")
iex("\"hello #{\"world\"}\"")  # String interpolation
```

## Debugging techniques

### Inspect intermediate steps
```elixir
iex("""
[1, 2, 3, 4]
|> IO.inspect(label: "original")
|> Enum.map(&(&1 * 2))
|> IO.inspect(label: "doubled")
|> Enum.sum()
|> IO.inspect(label: "sum")
""")
```

### Check type
```elixir
iex("is_binary(\"hello\")")
iex("is_atom(:hello)")
iex("is_list([1, 2, 3])")
```

### Timing operations
```elixir
iex(":timer.tc(fn -> Enum.reduce(1..10000, 0, &+/2) end)")
```

## When to use IEx tool

✅ **Good use cases:**
- Testing a function before writing it to a file
- Validating regex patterns
- Exploring data structures
- Quick calculations
- Checking if a module/function exists

❌ **Don't use for:**
- Long-running operations (use shell tool instead)
- File I/O (use read_file/write_file tools)
- Installing dependencies (use shell + mix commands)

## Best practices

1. **Keep it simple**: IEx is for quick tests, not full programs
2. **Use multiline strings** for complex expressions (triple quotes `"""`)
3. **Variables persist**: You can build up state across multiple iex calls
4. **Check errors first**: If uncertain about syntax, test in IEx before editing files

## Example workflow

```elixir
# User asks: "How do I get unique values from a list?"

# Test it in IEx first
iex("Enum.uniq([1, 2, 2, 3, 3, 3])")
# => [1, 2, 3]

# Verify it works with strings
iex("Enum.uniq([\"apple\", \"banana\", \"apple\"])")
# => ["apple", "banana"]

# Then implement it in actual code
write_file(
  path: "lib/helper.ex",
  content: """
  defmodule Helper do
    def unique_values(list) do
      Enum.uniq(list)
    end
  end
  """
)
```
