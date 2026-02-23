---
name: elixir-mix-install-debug
description: Create and use Mix.install standalone scripts for debugging Elixir code, testing APIs, exploring libraries, and isolating problems. Use when you need to test third-party integrations, verify library behavior, debug signatures, or prototype solutions outside the main project.
---

# Elixir Mix.install Debug Script Workflow

## When to Use This Skill

Use standalone `.exs` debug scripts when you need to:

- **Isolate API integration issues** - Test API signatures, request formats, authentication
- **Explore new libraries** - Understand library APIs before integrating into main project
- **Debug complex problems** - Remove project dependencies to narrow down root cause
- **Test multiple approaches** - Compare different solutions side-by-side
- **Verify fixes** - Reproduce bugs in isolation before applying fixes to main codebase
- **Prototype features** - Quick proof-of-concept without modifying project

**Don't use for**:
- Unit tests (use ExUnit in `test/` directory)
- Production code (belongs in `lib/`)
- Simple one-line checks (use `iex` instead)

## Prerequisites

- Elixir 1.12+ (for Mix.install support)
- Project `.env` file with required credentials (if testing authenticated APIs)
- For Windows users: WSL or Git configured with `core.autocrlf input`

## Instructions

### Step 1: Identify What Needs Debugging

Ask yourself:
- What specific behavior am I trying to understand or fix?
- Can I isolate this from the rest of the project?
- What dependencies does this require?

**Common scenarios**:
- Third-party API returning unexpected errors
- Library behaving differently than documented
- Signature/authentication issues
- Response parsing problems
- Multimodal content handling (images, audio)

### Step 2: Choose the Right Template

Select from `templates/` based on your scenario:

| Template | Use When | Example |
|----------|----------|---------|
| `basic.exs` | Testing HTTP APIs, simple library functions | API client testing, signature debugging |
| `liveview.exs` | Testing Phoenix LiveView components interactively | Upload flows, form interactions |
| `multimodal.exs` | Working with images, audio, or other media | Vision APIs, content parsing |
| `dotenv_loader.exs` | Just the DotEnv module for custom scripts | Building your own script from scratch |

**Copy the template**:
```bash
# From project root
cp .factory/skills/elixir-mix-install-debug/templates/basic.exs scripts/my_debug.exs
```

### Step 3: Configure Dependencies

Edit the `Mix.install/1` block in your script:

```elixir
Mix.install([
  {:req, "~> 0.5"},           # From Hex.pm
  {:my_lib, "~> 1.0"},        # Add needed dependencies
  # {:local_lib, path: "../my_lib", override: true},  # Local testing
  # {:pr_lib, github: "user/repo", branch: "fix-123", override: true}  # Test PR
])
```

**Common patterns**:
- Use `override: true` when dependency conflicts arise
- Test GitHub branches before merging: `github: "user/repo", branch: "feature"`
- Test local changes: `path: "../relative/path"`

### Step 4: Load Environment Variables

The templates include the `DotEnv` module that handles `.env` files:

```elixir
DotEnv.load()  # Searches .env, ../.env, ../../.env

# Then access variables
api_key = System.get_env("API_KEY") || raise "API_KEY not set"
```

**Tips**:
- DotEnv gracefully handles missing files
- Add fallback values for non-sensitive defaults
- Mask sensitive values in debug output

### Step 5: Structure Your Tests

Organize your script into clear sections:

```elixir
# ============================================================================
# Configuration
# ============================================================================
config = %{
  api_key: System.get_env("API_KEY"),
  endpoint: "https://api.example.com"
}

IO.puts("=== Configuration ===")
IO.inspect(config, pretty: true)

# ============================================================================
# Test 1: Basic Request
# ============================================================================
IO.puts("\n=== Test 1: Basic Request ===")
# Test code...

# ============================================================================
# Test 2: With Parameters
# ============================================================================
IO.puts("\n=== Test 2: With Parameters ===")
# Test code...
```

**Best practices**:
- Print clear section headers
- Use `IO.inspect/2` with labels for debugging
- Test one thing at a time
- Include both success and failure cases

### Step 6: Run and Debug

Execute your script:

```bash
# Method 1: Direct execution (if script has shebang)
chmod +x scripts/my_debug.exs
./scripts/my_debug.exs

# Method 2: Via elixir command
elixir scripts/my_debug.exs

# Method 3: In WSL (for Windows users)
wsl -e bash -c "cd /mnt/f/path/to/project && elixir scripts/my_debug.exs"
```

**Common issues**:

| Problem | Solution |
|---------|----------|
| Syntax errors with backslashes | Run `mix format scripts/my_debug.exs` to fix CRLF issues |
| "Module X not available" | Add missing dependency to Mix.install |
| Environment variable nil | Check DotEnv loaded before accessing, verify .env file exists |
| Dependency conflict | Add `override: true` to dependency spec |

### Step 7: Extract Learnings

Once you've isolated the problem:

1. **Document the finding** - Add comments to the script explaining what worked
2. **Update main codebase** - Apply the fix to your project code
3. **Keep or delete script**:
   - Keep if it's a reusable test (rename to `xxx_demo.exs`)
   - Delete if it was one-time debugging (cleanup `test_*.exs`)
4. **Update documentation** - Note the issue and solution in project docs

**Script naming conventions**:
- `xxx_demo.exs` - Reusable demonstrations/explorations (keep in repo)
- `xxx_test.exs` - Problem debugging/verification (can delete after)
- `test_xxx.exs` - Temporary debugging (clean up after solving)

## Advanced Patterns

### Testing Multiple Approaches

```elixir
approaches = [
  {"Approach A", fn -> method_a() end},
  {"Approach B", fn -> method_b() end},
  {"Approach C", fn -> method_c() end}
]

Enum.each(approaches, fn {name, func} ->
  IO.puts("\n=== #{name} ===")
  case func.() do
    {:ok, result} -> IO.puts("✅ Success: #{inspect(result)}")
    {:error, reason} -> IO.puts("❌ Failed: #{inspect(reason)}")
  end
end)
```

### Mock vs Real API Testing

From `scripts/cot_debug.exs` pattern:

```elixir
mode = if System.get_env("API_KEY"), do: :real, else: :mock

case mode do
  :real -> run_real_api_call()
  :mock -> run_mock_simulation()
end
```

### Generating curl Commands

Useful for comparing Elixir behavior with raw HTTP:

```elixir
IO.puts("""
Test with curl:
curl -X POST '#{url}' \\
  -H 'Authorization: Bearer #{api_key}' \\
  -d '#{Jason.encode!(body)}'
""")
```

## Verification

Before considering the script complete:

- [ ] Script runs without syntax errors
- [ ] All environment variables are loaded correctly
- [ ] Dependencies install successfully
- [ ] Test cases produce expected output
- [ ] Windows users: Run `mix format scripts/my_debug.exs` to fix line endings
- [ ] Sensitive data (API keys) are masked in output
- [ ] Script includes clear comments explaining the purpose

## Examples from Project

Refer to these existing scripts for patterns:

- **`scripts/test_r2_delete.exs`** - Debugging AWS signature issues, includes curl output
- **`scripts/req_llm_pic_demo.exs`** - Multimodal API testing with ReqLLM
- **`scripts/s3_upload_demo.exs`** - Phoenix LiveView + external uploads with Buckets
- **`scripts/jido_demo.exs`** - Testing library from GitHub branch
- **`scripts/cot_debug.exs`** - Dual-mode (real/mock) testing with Phoenix Playground

## Troubleshooting

### Windows + WSL Issues

**CRLF Line Endings**:
```bash
# Fix with mix format
mix format scripts/my_debug.exs

# Or configure git globally
git config --global core.autocrlf input
```

**Path Issues**:
```bash
# Windows path: F:\Fcode\web\project
# WSL path: /mnt/f/Fcode/web/project
```

### Dependency Issues

**Conflict Resolution**:
```elixir
Mix.install([
  {:conflicting_lib, "~> 1.0", override: true}  # Force this version
])
```

**Clear Cache**:
```bash
rm -rf ~/.mix/installs/
```

### Environment Loading

**Debug DotEnv**:
```elixir
# Add debug output to DotEnv.load/1
IO.puts("🔍 Checking: .env, ../.env, ../../.env")
IO.puts("✅ Loaded: #{path}") # When found
```

## Next Steps

After successfully debugging:

1. Apply findings to main codebase
2. Consider adding ExUnit tests for regression prevention
3. Update relevant documentation
4. Clean up temporary test scripts
5. Share learnings with team (commit demo scripts if valuable)

---

**Tip**: Keep valuable debug scripts in `scripts/` directory and commit them to git. They serve as executable documentation and can be reused by teammates.
