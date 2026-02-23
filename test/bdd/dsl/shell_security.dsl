[SCENARIO: SHELL-SEC-001] TITLE: Safe commands are allowed
  WHEN check_shell_command command="ls -la" session_id="shell_test"
  THEN assert_approval_required required=false

  WHEN check_shell_command command="echo 'hello'" session_id="shell_test"
  THEN assert_approval_required required=false

[SCENARIO: SHELL-SEC-002] TITLE: Dangerous commands require approval
  WHEN check_shell_command command="rm -rf /" session_id="shell_test"
  THEN assert_approval_required required=true reason="Deleting files"

  WHEN check_shell_command command="npm install" session_id="shell_test"
  THEN assert_approval_required required=true reason="Installing npm packages"

[SCENARIO: SHELL-SEC-003] TITLE: Case sensitivity and compound commands
  # Currently ShellInterceptor uses case-sensitive matching anchored to start
  # So RM and ls && rm are NOT intercepted.
  # We document current behavior here.
  
  WHEN check_shell_command command="RM -rf file" session_id="shell_test"
  THEN assert_approval_required required=false
  
  WHEN check_shell_command command="ls && rm file" session_id="shell_test"
  THEN assert_approval_required required=false
