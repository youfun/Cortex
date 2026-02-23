%{
  start_agent: %{
    name: :start_agent,
    kind: :given,
    args: %{
      session_id: %{type: :string, required?: false, allowed: nil}
    },
    outputs: %{},
    boundary: :tool,
    scopes: [:integration]
  },
  restart_agent: %{
    name: :restart_agent,
    kind: :when,
    args: %{
      session_id: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :tool,
    scopes: [:integration]
  },
  shell: %{
    name: :shell,
    kind: :given,
    args: %{
      command: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :tool,
    scopes: [:integration]
  },
  classify_error: %{
    name: :classify_error,
    kind: :when,
    args: %{
      error: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    rules: [],
    boundary: :test_runtime,
    scopes: [:unit],
    async?: false,
    eventually?: false,
    assert_class: nil
  },
  retry_delay: %{
    name: :retry_delay,
    kind: :when,
    args: %{
      attempt: %{type: :int, required?: true, allowed: nil}
    },
    outputs: %{},
    rules: [],
    boundary: :test_runtime,
    scopes: [:unit],
    async?: false,
    eventually?: false,
    assert_class: nil
  },
  retry_should_retry: %{
    name: :retry_should_retry,
    kind: :when,
    args: %{
      error_class: %{type: :string, required?: true, allowed: nil},
      attempt: %{type: :int, required?: true, allowed: nil}
    },
    outputs: %{},
    rules: [],
    boundary: :test_runtime,
    scopes: [:unit],
    async?: false,
    eventually?: false,
    assert_class: nil
  },
  assert_error_class: %{
    name: :assert_error_class,
    kind: :then,
    args: %{
      expected: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    rules: [],
    boundary: :test_runtime,
    scopes: [:unit],
    async?: false,
    eventually?: false,
    assert_class: :C
  },
  assert_delay_ms: %{
    name: :assert_delay_ms,
    kind: :then,
    args: %{
      expected: %{type: :int, required?: true, allowed: nil}
    },
    outputs: %{},
    rules: [],
    boundary: :test_runtime,
    scopes: [:unit],
    async?: false,
    eventually?: false,
    assert_class: :C
  },
  assert_should_retry: %{
    name: :assert_should_retry,
    kind: :then,
    args: %{
      expected: %{type: :bool, required?: true, allowed: nil}
    },
    outputs: %{},
    rules: [],
    boundary: :test_runtime,
    scopes: [:unit],
    async?: false,
    eventually?: false,
    assert_class: :C
  },
  estimate_tokens: %{
    name: :estimate_tokens,
    kind: :when,
    args: %{
      text: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    rules: [],
    boundary: :test_runtime,
    scopes: [:unit],
    async?: false,
    eventually?: false,
    assert_class: nil
  },
  assert_tokens: %{
    name: :assert_tokens,
    kind: :then,
    args: %{
      expected: %{type: :int, required?: true, allowed: nil}
    },
    outputs: %{},
    rules: [],
    boundary: :test_runtime,
    scopes: [:unit],
    async?: false,
    eventually?: false,
    assert_class: :C
  },
  sliding_window_split: %{
    name: :sliding_window_split,
    kind: :when,
    args: %{
      messages: %{type: :string, required?: true, allowed: nil},
      window_size: %{type: :int, required?: false, allowed: nil}
    },
    outputs: %{},
    rules: [],
    boundary: :test_runtime,
    scopes: [:unit],
    async?: false,
    eventually?: false,
    assert_class: nil
  },
  assert_window_size: %{
    name: :assert_window_size,
    kind: :then,
    args: %{
      target: %{type: :string, required?: true, allowed: ["old", "recent"]},
      expected: %{type: :int, required?: true, allowed: nil}
    },
    outputs: %{},
    rules: [],
    boundary: :test_runtime,
    scopes: [:unit],
    async?: false,
    eventually?: false,
    assert_class: :C
  },
  truncate_tool_outputs: %{
    name: :truncate_tool_outputs,
    kind: :when,
    args: %{
      messages: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    rules: [],
    boundary: :test_runtime,
    scopes: [:unit],
    async?: false,
    eventually?: false,
    assert_class: nil
  },
  compact: %{
    name: :compact,
    kind: :when,
    args: %{
      messages: %{type: :string, required?: true, allowed: nil},
      model: %{type: :string, required?: false, allowed: nil}
    },
    outputs: %{},
    rules: [],
    boundary: :test_runtime,
    scopes: [:unit],
    async?: false,
    eventually?: false,
    assert_class: nil
  },
  assert_messages_count: %{
    name: :assert_messages_count,
    kind: :then,
    args: %{
      expected: %{type: :int, required?: true, allowed: nil}
    },
    outputs: %{},
    rules: [],
    boundary: :test_runtime,
    scopes: [:unit],
    async?: false,
    eventually?: false,
    assert_class: :C
  },
  assert_message_content: %{
    name: :assert_message_content,
    kind: :then,
    args: %{
      index: %{type: :int, required?: true, allowed: nil},
      contains: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    rules: [],
    boundary: :test_runtime,
    scopes: [:unit],
    async?: false,
    eventually?: false,
    assert_class: :C
  },
  truncate_head: %{
    name: :truncate_head,
    kind: :when,
    args: %{
      content_var: %{type: :string, required?: true, allowed: nil},
      max_lines: %{type: :int, required?: false, allowed: nil},
      max_bytes: %{type: :int, required?: false, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:unit, :integration],
    async?: false,
    eventually?: false,
    assert_class: nil
  },
  truncate_tail: %{
    name: :truncate_tail,
    kind: :when,
    args: %{
      content_var: %{type: :string, required?: true, allowed: nil},
      max_lines: %{type: :int, required?: false, allowed: nil},
      max_bytes: %{type: :int, required?: false, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:unit, :integration],
    async?: false,
    eventually?: false,
    assert_class: nil
  },
  truncate_line: %{
    name: :truncate_line,
    kind: :when,
    args: %{
      content_var: %{type: :string, required?: true, allowed: nil},
      max_chars: %{type: :int, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:unit, :integration],
    async?: false,
    eventually?: false,
    assert_class: nil
  },
  parse_skill_command: %{
    name: :parse_skill_command,
    kind: :when,
    args: %{
      input: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:unit, :integration],
    async?: false,
    eventually?: false,
    assert_class: nil
  },
  assert_skill_command: %{
    name: :assert_skill_command,
    kind: :then,
    args: %{
      name: %{type: :string, required?: false, allowed: nil},
      contains: %{type: :string, required?: false, allowed: nil},
      matched: %{type: :bool, required?: false, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:unit, :integration],
    async?: false,
    eventually?: false,
    assert_class: :C
  },
  assert_truncation_result: %{
    name: :assert_truncation_result,
    kind: :then,
    args: %{
      truncated: %{type: :bool, required?: false, allowed: nil},
      truncated_by: %{type: :string, required?: false, allowed: nil},
      output_lines: %{type: :int, required?: false, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:unit, :integration],
    async?: false,
    eventually?: false,
    assert_class: :C
  },
  execute_tool: %{
    name: :execute_tool,
    kind: :when,
    args: %{
      tool_name: %{type: :string, required?: true, allowed: nil},
      args: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :tool,
    scopes: [:unit, :integration],
    async?: false,
    eventually?: false,
    assert_class: nil
  },
  assert_tool_result: %{
    name: :assert_tool_result,
    kind: :then,
    args: %{
      contains: %{type: :string, required?: false, allowed: nil},
      truncated: %{type: :bool, required?: false, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:unit, :integration],
    async?: false,
    eventually?: false,
    assert_class: :C
  },
  steering_inject: %{
    name: :steering_inject,
    kind: :when,
    args: %{
      content: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :tool,
    scopes: [:integration],
    async?: false,
    eventually?: false,
    assert_class: nil
  },
  assert_steering_queue_size: %{
    name: :assert_steering_queue_size,
    kind: :then,
    args: %{
      expected: %{type: :int, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:integration],
    async?: false,
    eventually?: false,
    assert_class: :C
  },
  signal_bus_is_clean: %{
    name: :signal_bus_is_clean,
    kind: :given,
    args: %{},
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:integration],
    async?: false,
    eventually?: false,
    assert_class: nil
  },
  signal_is_emitted: %{
    name: :signal_is_emitted,
    kind: :when,
    args: %{
      type: %{type: :string, required?: true, allowed: nil},
      data: %{type: :string, required?: true, allowed: nil},
      session_id: %{type: :string, required?: false, allowed: nil}
    },
    outputs: %{},
    boundary: :tool,
    scopes: [:integration],
    async?: false,
    eventually?: false,
    assert_class: nil
  },
  emit_signal: %{
    name: :emit_signal,
    kind: :when,
    args: %{
      type: %{type: :string, required?: true, allowed: nil},
      data: %{type: :string, required?: true, allowed: nil},
      session_id: %{type: :string, required?: false, allowed: nil}
    },
    outputs: %{},
    boundary: :tool,
    scopes: [:integration],
    async?: false,
    eventually?: false,
    assert_class: nil
  },
  history_file_should_not_contain: %{
    name: :history_file_should_not_contain,
    kind: :then,
    args: %{
      type: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:integration],
    async?: false,
    eventually?: true,
    assert_class: :C
  },
  history_file_should_contain: %{
    name: :history_file_should_contain,
    kind: :then,
    args: %{
      type: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:integration],
    async?: false,
    eventually?: true,
    assert_class: :C
  },
  assert_signal_emitted: %{
    name: :assert_signal_emitted,
    kind: :then,
    args: %{
      type: %{type: :string, required?: true, allowed: nil},
      session_id: %{type: :string, required?: false, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:integration],
    async?: false,
    eventually?: true,
    assert_class: :C
  },
  tape_should_contain_entry: %{
    name: :tape_should_contain_entry,
    kind: :then,
    args: %{
      type: %{type: :string, required?: true, allowed: nil},
      content: %{type: :string, required?: false, allowed: nil},
      session_id: %{type: :string, required?: false, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:integration],
    async?: false,
    eventually?: true,
    assert_class: :C
  },
  tape_should_not_contain_entry: %{
    name: :tape_should_not_contain_entry,
    kind: :then,
    args: %{
      type: %{type: :string, required?: true, allowed: nil},
      content: %{type: :string, required?: false, allowed: nil},
      session_id: %{type: :string, required?: false, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:integration],
    async?: false,
    eventually?: true,
    assert_class: :C
  },
  create_tape_branch: %{
    name: :create_tape_branch,
    kind: :when,
    args: %{
      source: %{type: :string, required?: true, allowed: nil},
      target: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :tool,
    scopes: [:integration],
    async?: false,
    eventually?: false,
    assert_class: nil
  },
  create_session_branch: %{
    name: :create_session_branch,
    kind: :when,
    args: %{
      parent_session_id: %{type: :string, required?: true, allowed: nil},
      purpose: %{type: :string, required?: false, allowed: nil},
      branch_id: %{type: :string, required?: false, allowed: nil}
    },
    outputs: %{},
    boundary: :tool,
    scopes: [:integration],
    async?: false,
    eventually?: false,
    assert_class: nil
  },
  tape_entry_count_should_be: %{
    name: :tape_entry_count_should_be,
    kind: :then,
    args: %{
      session_id: %{type: :string, required?: true, allowed: nil},
      expected: %{type: :int, required?: true, allowed: nil},
      limit: %{type: :int, required?: false, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:integration],
    async?: false,
    eventually?: true,
    assert_class: :C
  },
  tape_branch_point_should_be: %{
    name: :tape_branch_point_should_be,
    kind: :then,
    args: %{
      branch_session_id: %{type: :string, required?: true, allowed: nil},
      expected: %{type: :int, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:integration],
    async?: false,
    eventually?: true,
    assert_class: :C
  },
  assert_agent_history_count: %{
    name: :assert_agent_history_count,
    kind: :then,
    args: %{
      session_id: %{type: :string, required?: true, allowed: nil},
      min_count: %{type: :int, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:integration],
    async?: false,
    eventually?: true,
    assert_class: :C
  },
  estimate_messages: %{
    name: :estimate_messages,
    kind: :when,
    args: %{
      messages: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    rules: [],
    boundary: :test_runtime,
    scopes: [:unit],
    async?: false,
    eventually?: false,
    assert_class: nil
  },
  assert_total_tokens: %{
    name: :assert_total_tokens,
    kind: :then,
    args: %{
      expected: %{type: :int, required?: true, allowed: nil}
    },
    outputs: %{},
    rules: [],
    boundary: :test_runtime,
    scopes: [:unit],
    async?: false,
    eventually?: false,
    assert_class: :C
  },
  register_dynamic_tool: %{
    name: :register_dynamic_tool,
    kind: :when,
    args: %{
      tool_name: %{type: :string, required?: true, allowed: nil},
      description: %{type: :string, required?: false, allowed: nil}
    },
    outputs: %{},
    boundary: :tool,
    scopes: [:integration]
  },
  unregister_dynamic_tool: %{
    name: :unregister_dynamic_tool,
    kind: :when,
    args: %{
      tool_name: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :tool,
    scopes: [:integration]
  },
  assert_tool_available: %{
    name: :assert_tool_available,
    kind: :then,
    args: %{
      tool_name: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:integration],
    assert_class: :C
  },
  assert_tool_not_available: %{
    name: :assert_tool_not_available,
    kind: :then,
    args: %{
      tool_name: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:integration],
    assert_class: :C
  },
  load_extension: %{
    name: :load_extension,
    kind: :when,
    args: %{
      module: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :tool,
    scopes: [:integration]
  },
  unload_extension: %{
    name: :unload_extension,
    kind: :when,
    args: %{
      module: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :tool,
    scopes: [:integration]
  },
  assert_extension_loaded: %{
    name: :assert_extension_loaded,
    kind: :then,
    args: %{
      module: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:integration],
    assert_class: :C
  },
  assert_extension_not_loaded: %{
    name: :assert_extension_not_loaded,
    kind: :then,
    args: %{
      module: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:integration],
    assert_class: :C
  },
  assert_hooks_registered: %{
    name: :assert_hooks_registered,
    kind: :then,
    args: %{
      hooks: %{type: :string, required?: true, allowed: nil},
      session_id: %{type: :string, required?: false, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:integration],
    assert_class: :C
  },
  assert_hooks_unregistered: %{
    name: :assert_hooks_unregistered,
    kind: :then,
    args: %{
      hooks: %{type: :string, required?: true, allowed: nil},
      session_id: %{type: :string, required?: false, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:integration],
    assert_class: :C
  },
  assert_tools_registered: %{
    name: :assert_tools_registered,
    kind: :then,
    args: %{
      tools: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:integration],
    assert_class: :C
  },
  wait_for_turn_complete: %{
    name: :wait_for_turn_complete,
    kind: :then,
    args: %{
      session_id: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:integration],
    async?: false,
    eventually?: true
  },
  assert_tools_unregistered: %{
    name: :assert_tools_unregistered,
    kind: :then,
    args: %{
      tools: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:integration],
    assert_class: :C
  },
  send_chat_message: %{
    name: :send_chat_message,
    kind: :when,
    args: %{
      session_id: %{type: :string, required?: true, allowed: nil},
      content: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :tool,
    scopes: [:integration]
  },
  assert_signal_data: %{
    name: :assert_signal_data,
    kind: :then,
    args: %{
      type: %{type: :string, required?: true, allowed: nil},
      path: %{type: :string, required?: true, allowed: nil},
      expected: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:integration],
    async?: false,
    eventually?: true,
    assert_class: :C
  },
  check_permission: %{
    name: :check_permission,
    kind: :when,
    args: %{
      actor: %{type: :string, required?: true, allowed: nil},
      action: %{type: :string, required?: true, allowed: nil},
      context: %{type: :string, required?: false, allowed: nil},
      session_id: %{type: :string, required?: false, allowed: nil}
    },
    outputs: %{},
    boundary: :tool,
    scopes: [:integration]
  },
  resolve_permission_request: %{
    name: :resolve_permission_request,
    kind: :when,
    args: %{
      request_id: %{type: :string, required?: true, allowed: nil},
      decision: %{type: :string, required?: true, allowed: ["allow", "deny"]},
      duration: %{type: :string, required?: false, allowed: ["once", "always"]},
      session_id: %{type: :string, required?: false, allowed: nil}
    },
    outputs: %{},
    boundary: :tool,
    scopes: [:integration]
  },
  assert_authorized: %{
    name: :assert_authorized,
    kind: :then,
    args: %{
      actor: %{type: :string, required?: true, allowed: nil},
      action: %{type: :string, required?: true, allowed: nil},
      expected: %{type: :bool, required?: true, allowed: nil},
      session_id: %{type: :string, required?: false, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:integration],
    assert_class: :C
  },
  check_shell_command: %{
    name: :check_shell_command,
    kind: :when,
    args: %{
      command: %{type: :string, required?: true, allowed: nil},
      session_id: %{type: :string, required?: false, allowed: nil}
    },
    outputs: %{},
    boundary: :tool,
    scopes: [:integration]
  },
  assert_approval_required: %{
    name: :assert_approval_required,
    kind: :then,
    args: %{
      required: %{type: :bool, required?: true, allowed: nil},
      reason: %{type: :string, required?: false, allowed: nil}
    },
    outputs: %{},
    boundary: :test_runtime,
    scopes: [:integration],
    assert_class: :C
  },
  stop_session: %{
    name: :stop_session,
    kind: :when,
    args: %{
      session_id: %{type: :string, required?: true, allowed: nil}
    },
    outputs: %{},
    boundary: :tool,
    scopes: [:integration]
  },
  switch_session: %{
    name: :switch_session,
    kind: :when,
    args: %{
      old_session_id: %{type: :string, required?: true, allowed: nil},
      new_session_id: %{type: :string, required?: true, allowed: nil},
      opts: %{type: :string, required?: false, allowed: nil}
    },
    outputs: %{},
    boundary: :tool,
    scopes: [:integration]
  },
  complete_session_branch: %{
    name: :complete_session_branch,
    kind: :when,
    args: %{
      branch_session_id: %{type: :string, required?: true, allowed: nil},
      result: %{type: :string, required?: false, allowed: nil}
    },
    outputs: %{},
    boundary: :tool,
    scopes: [:integration]
  },
  merge_session_branch: %{
    name: :merge_session_branch,
    kind: :when,
    args: %{
      branch_session_id: %{type: :string, required?: true, allowed: nil},
      target_session_id: %{type: :string, required?: true, allowed: nil},
      strategy: %{type: :string, required?: false, allowed: nil}
    },
    outputs: %{},
    boundary: :tool,
    scopes: [:integration]
  }
}
