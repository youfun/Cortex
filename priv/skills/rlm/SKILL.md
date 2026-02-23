---
name: rlm
description: Recursive Language Model pattern for analyzing data too large for a single context window
---

# RLM (Recursive Language Model) Skill

## When to Use

Use this pattern when:
- Data exceeds ~50KB (logs, codebases, datasets)
- Single-pass analysis produces low quality results
- You need to aggregate insights from multiple data segments

## Available Functions (in iex)

- `llm_query.(prompt, data)` — Query sub-LLM with default model
- `llm_query_with_model.(model, prompt, data)` — Query with specific model
- `llm_query_many.(chunks, prompt)` — Parallel batch query (default concurrency: 4)
- `llm_query_many.(chunks, prompt, max_concurrency: 8, model: "gpt-4o")` — With options

## Pattern: Explore → Chunk → Analyze → Synthesize

### Step 1: Load & Explore
```elixir
iex> raw = File.read!("/path/to/large_file.log")
iex> lines = String.split(raw, "\n")
iex> length(lines)  # Check size
iex> Enum.take(lines, 5)  # Sample first few lines
```

### Step 2: Chunk
```elixir
iex> chunks = Enum.chunk_every(lines, 500) |> Enum.map(&Enum.join(&1, "\n"))
iex> length(chunks)  # How many chunks?
```

### Step 3: Parallel Analyze
```elixir
iex> results = llm_query_many.(chunks, "Identify error patterns and anomalies in this log segment. Return a bullet list.")
```

### Step 4: Synthesize
```elixir
iex> combined = Enum.with_index(results, 1) |> Enum.map(fn {r, i} -> "## Chunk #{i}\n#{r}" end) |> Enum.join("\n\n")
iex> summary = llm_query.("Synthesize these analyses into a final report with root causes and recommendations:", combined)
```

## Tips

- Start with `Enum.take(lines, 10)` to understand data structure before chunking
- Use `shell("wc -l /path/to/file")` to check file size first
- For code analysis, chunk by module/function rather than line count
- Keep chunk size at 300-800 lines for best sub-LLM accuracy
- Use `write_file` to save the final synthesis report
