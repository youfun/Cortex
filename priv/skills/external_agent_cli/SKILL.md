---
name: external-agent-cli
description: Invoke external agent CLIs (codex/gemini/claude) via shell from chat.
always: true
---

# External Agent CLI Skill

Use this skill when the user asks to run an external agent CLI from chat.

## Trigger
User message starts with:
- `/skill external-agent-cli <prompt>`
- `@skill external-agent-cli <prompt>`

## Behavior (Mandatory)
1. Choose the CLI based on user intent:
   - `codex` for general coding tasks
   - `gemini` for fast analysis or summarization
   - `claude` for long-form reasoning or drafting
2. Execute via the `shell` tool.
3. Return the CLI output verbatim. Do NOT rewrite, paraphrase, or regenerate content.

## Shell Execution (Strict)
You MUST use heredoc to avoid quoting errors. Do NOT use `gemini "<prompt>"` or similar.

Required format:
```bash
cat <<'EOF' | gemini
<user prompt here>
EOF
```

This applies to all CLIs:
- `codex`: `cat <<'EOF' | codex`
- `gemini`: `cat <<'EOF' | gemini`
- `claude`: `cat <<'EOF' | claude`

## Examples
- User: `/skill external-agent-cli generate a refactor plan for lib/cortex/agents`
- Action: run `shell` with a CLI command, then summarize the output.

## Shell Command Templates (Strict)
- `codex`:
```bash
cat <<'EOF' | codex
<prompt>
EOF
```
- `gemini`:
```bash
cat <<'EOF' | gemini
<prompt>
EOF
```
- `claude`:
```bash
cat <<'EOF' | claude
<prompt>
EOF
```

## Safety
- Do not run destructive commands.
- If the CLI requires approval, wait for user approval.
