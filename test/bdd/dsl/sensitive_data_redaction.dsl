# Sensitive Data Redaction BDD Test
# Verifies that sensitive data in files is redacted before returning to Agent/LLM.

[SCENARIO: REDACT-001] TITLE: Env file values are redacted TAGS: unit security
  LET env_content = 'DATABASE_URL=postgres://user:secret123@localhost/db\nAPI_KEY=sk-1234567890abcdef\nAPP_NAME=my_app'
  LET write_args = '{"path":".env.test_redact","content":"DATABASE_URL=postgres://user:secret123@localhost/db\\nAPI_KEY=sk-1234567890abcdef\\nAPP_NAME=my_app"}'
  WHEN execute_tool tool_name="write_file" args=$write_args
  WHEN execute_tool tool_name="read_file" args='{"path":".env.test_redact"}'
  THEN assert_tool_result contains="[REDACTED]"
  THEN assert_tool_result_not_contains value="secret123"
  THEN assert_tool_result_not_contains value="sk-1234567890abcdef"
  THEN assert_tool_result contains="APP_NAME"

[SCENARIO: REDACT-002] TITLE: Normal code files are not redacted TAGS: unit security
  LET write_args = '{"path":"lib/test_normal.ex","content":"defmodule TestNormal do\\n  def hello, do: :world\\nend"}'
  WHEN execute_tool tool_name="write_file" args=$write_args
  WHEN execute_tool tool_name="read_file" args='{"path":"lib/test_normal.ex"}'
  THEN assert_tool_result contains="defmodule TestNormal"
  THEN assert_tool_result contains="hello"

[SCENARIO: REDACT-003] TITLE: Full redact mode for key files TAGS: unit security
  LET write_args = '{"path":"test_secret.pem","content":"-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEA0Z3VS5JJcds3xfn/ygWyF8PbnGy0AHB7MhgHcTz6sE2I2yPB\naFDrBz9vFqU5xTL0+kSCPuf5LBaYeDZJHYdKxQ==\n-----END RSA PRIVATE KEY-----"}'
  WHEN execute_tool tool_name="write_file" args=$write_args
  WHEN execute_tool tool_name="read_file" args='{"path":"test_secret.pem"}'
  THEN assert_tool_result contains="[REDACTED:"
  THEN assert_tool_result_not_contains value="BEGIN RSA PRIVATE KEY"

[SCENARIO: REDACT-004] TITLE: Shell output is redacted TAGS: unit security
  LET write_args = '{"path":".env.test_shell_redact","content":"SECRET_KEY=abc123superSecret"}'
  WHEN execute_tool tool_name="write_file" args=$write_args
  WHEN execute_tool tool_name="shell" args='{"command":"cat .env.test_shell_redact"}'
  THEN assert_tool_result contains="[REDACTED]"
  THEN assert_tool_result_not_contains value="abc123superSecret"

[SCENARIO: REDACT-005] TITLE: Whitelisted files skip redaction TAGS: unit security
  LET write_args = '{"path":".env.example","content":"DATABASE_URL=your_database_url_here\nAPI_KEY=your_api_key_here"}'
  WHEN execute_tool tool_name="write_file" args=$write_args
  WHEN execute_tool tool_name="read_file" args='{"path":".env.example"}'
  THEN assert_tool_result contains="your_database_url_here"
