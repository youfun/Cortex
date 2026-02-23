# Mix.install Debug Script Checklists

## Pre-Run Checklist

Before executing your debug script, verify:

### Environment Setup
- [ ] `.env` file exists with required credentials (or you know they're set in shell)
- [ ] You're in the correct directory (project root or scripts/)
- [ ] Elixir version is 1.12+ (`elixir --version`)
- [ ] For Windows users: Git configured with `core.autocrlf input` or using WSL

### Script Validation
- [ ] Script has clear purpose documented in header comment
- [ ] All required dependencies listed in `Mix.install/1`
- [ ] DotEnv module included if loading from `.env`
- [ ] Config validation checks for required environment variables
- [ ] Test sections have clear labels/headers

### Common Gotchas
- [ ] No hardcoded secrets in the script (use environment variables)
- [ ] File paths are correct (relative paths from execution directory)
- [ ] API endpoints are correct (staging vs production)
- [ ] Network connectivity is available if testing external APIs

---

## Post-Run Checklist

After successfully debugging, complete these steps:

### Extract Findings
- [ ] Document what you discovered (add comments to script or update docs)
- [ ] Apply fix to main codebase if applicable
- [ ] Create or update ExUnit tests for regression prevention
- [ ] Update relevant documentation (API docs, troubleshooting guides)

### Script Management
- [ ] Decide: Keep or delete this script?
  - **Keep if**: Reusable demo, valuable reference, team might need it
  - **Delete if**: One-time debugging, problem solved, no future value
- [ ] If keeping: Rename to convention (`xxx_demo.exs` or `xxx_test.exs`)
- [ ] If keeping: Add to `.gitignore` if contains sensitive test data
- [ ] If keeping: Run `mix format scripts/your_script.exs` to ensure clean formatting

### Knowledge Sharing
- [ ] Share findings with team (Slack, docs, commit message)
- [ ] Update project's debugging guide if new pattern discovered
- [ ] Add script to `scripts/` directory if valuable for team
- [ ] Document any new environment variables needed in `.env.example`

---

## Windows + WSL Specific Checklist

If you're on Windows and encountering issues:

### Line Ending Issues
- [ ] Run `mix format scripts/your_script.exs` to fix CRLF issues
- [ ] Verify Git config: `git config core.autocrlf` should be `input`
- [ ] If editing in Windows, ensure your editor uses LF line endings

### Path Issues
- [ ] Converted Windows paths to WSL paths (`F:\path` → `/mnt/f/path`)
- [ ] Script uses forward slashes `/` not backslashes `\`
- [ ] Relative paths work from WSL's perspective

### Execution Context
- [ ] Running `elixir` from WSL, not Windows PowerShell
- [ ] Dependencies compile successfully in WSL environment
- [ ] `.env` file readable from WSL (check permissions)

### Quick Fix Commands
```bash
# Fix line endings
mix format scripts/your_script.exs

# Configure Git globally
git config --global core.autocrlf input

# Check file from WSL
wsl -e file scripts/your_script.exs
# Should show: "ASCII text" not "ASCII text, with CRLF"

# Convert if needed
wsl -e dos2unix scripts/your_script.exs
```

---

## Dependency Troubleshooting Checklist

If dependencies won't install or compile:

### Version Conflicts
- [ ] Added `override: true` to conflicting dependencies
- [ ] Checked Hex.pm for compatible version ranges
- [ ] Tried using exact versions instead of `~>` pessimistic operator
- [ ] Cleared dependency cache: `rm -rf ~/.mix/installs/`

### GitHub Dependencies
- [ ] Branch/tag exists in the repository
- [ ] Repository is public or you have SSH keys configured
- [ ] Used `override: true` if replacing Hex version
- [ ] Commit SHA is correct if using `ref:` option

### Local Dependencies
- [ ] Path is relative to script location
- [ ] Local dependency has valid `mix.exs`
- [ ] Local dependency compiles independently
- [ ] Used `override: true` to force local version

### Common Solutions
```elixir
# Conflict resolution
{:my_lib, "~> 1.0", override: true}

# Test GitHub PR
{:my_lib, github: "user/repo", branch: "fix-issue-123", override: true}

# Local development
{:my_lib, path: "../my_lib", override: true}

# Specific commit
{:my_lib, github: "user/repo", ref: "abc1234", override: true}
```

---

## API Testing Checklist

When debugging API integrations:

### Before Testing
- [ ] API credentials are valid and not expired
- [ ] Correct API endpoint (check documentation)
- [ ] Rate limits won't be exceeded
- [ ] Test data won't pollute production
- [ ] Network allows outbound connections

### During Testing
- [ ] Log full request/response for debugging
- [ ] Mask sensitive data in logs (API keys, tokens)
- [ ] Test with minimal data first
- [ ] Verify request headers match documentation
- [ ] Check response status codes and error messages

### Response Handling
- [ ] Handle success cases (200, 201, 204)
- [ ] Handle client errors (400, 401, 403, 404)
- [ ] Handle server errors (500, 502, 503)
- [ ] Handle network timeouts
- [ ] Parse error messages correctly

### Useful Debug Outputs
```elixir
# Log request for comparison with curl
IO.puts("""
curl -X POST '#{url}' \\
  -H 'Authorization: Bearer #{api_key}' \\
  -H 'Content-Type: application/json' \\
  -d '#{Jason.encode!(body)}'
""")

# Inspect full response
IO.inspect(response, label: "Response", limit: :infinity, pretty: true)

# Check specific fields
IO.puts("Status: #{response.status}")
IO.puts("Headers: #{inspect(response.headers)}")
```

---

## Completion Checklist

Before moving on from your debugging session:

- [ ] Problem is fully understood and documented
- [ ] Solution is tested and verified
- [ ] Main codebase is updated with fix
- [ ] Tests added to prevent regression
- [ ] Script is cleaned up (formatted, commented)
- [ ] Script is saved/deleted according to its value
- [ ] Knowledge is shared with team
- [ ] `.env` variables documented if new ones added
- [ ] Any temporary files or test data cleaned up

**Ready to commit?** If keeping the script, add it to your commit with the main fix so it serves as executable documentation of the problem and solution.
