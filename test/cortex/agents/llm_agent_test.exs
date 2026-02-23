defmodule Cortex.Agents.LLMAgentTest do
  use Cortex.DataCase, async: false
  use Mimic

  alias Cortex.Agents.LLMAgent
  alias Cortex.LLM.Client
  alias Cortex.Tools.ToolRunner
  alias ReqLLM.Response

  setup %{owner_pid: owner_pid} do
    # Mock Config to avoid DB lookup
    stub(Cortex.LLM.Config, :get, fn model ->
      {:ok, "google:#{model}", [model: model, api_key: "test", base_url: "test"]}
    end)

    set_mimic_global()

    # Ensure PubSub is started
    if Process.whereis(Cortex.PubSub) == nil do
      Phoenix.PubSub.Supervisor.start_link(name: Cortex.PubSub, adapter: Phoenix.PubSub.PG2)
    end

    # Ensure SessionRegistry is started
    if Process.whereis(Cortex.SessionRegistry) == nil do
      Registry.start_link(keys: :unique, name: Cortex.SessionRegistry)
    end

    # Ensure AgentTaskSupervisor is started
    if Process.whereis(Cortex.AgentTaskSupervisor) == nil do
      Task.Supervisor.start_link(name: Cortex.AgentTaskSupervisor)
    end

    session_id = "session_#{System.unique_integer([:positive])}"

    # Create conversation to satisfy FK constraints for Writer
    # We use a raw insert or struct if available.
    # Assuming Conversation schema exists.
    # If not, we might need to inspect the schema.
    # Using raw SQL might be safer if we don't want to depend on schema modules in test setup too much,
    # but using Schema is standard.

    # Let's try to insert a dummy conversation.
    # conversation_id is string.
    conversation_id = String.replace(session_id, "session_", "")

    %Cortex.Conversations.Conversation{id: conversation_id, title: "Test", status: "active"}
    |> Cortex.Repo.insert!()

    Phoenix.PubSub.subscribe(Cortex.PubSub, "jido.studio.session:#{session_id}")
    Cortex.SignalHub.subscribe("**")

    {:ok, pid} = LLMAgent.start_link(session_id: session_id)
    Cortex.DataCase.allow_process(owner_pid, pid)
    %{pid: pid, session_id: session_id}
  end

  test "chat updates history and calls LLM", %{pid: pid} do
    # Mock Response functions
    stub(Response, :text, fn _ -> "Hello World" end)
    stub(Response, :tool_calls, fn _ -> [] end)

    # Mock Client
    stub(Client, :stream_chat, fn _model, context, opts ->
      if on_chunk = opts[:on_chunk] do
        on_chunk.("Hello")
        on_chunk.(" World")
      end

      # Simulate a success result containing the message and context
      {:ok,
       %{
         message: %{role: "assistant", content: "Hello World"},
         context: ReqLLM.Context.append(context, ReqLLM.Context.assistant("Hello World"))
       }}
    end)

    :ok = LLMAgent.chat(pid, "Hi")

    # Verify stream events (Signals are wrapped in {:signal, ...} when via SignalHub subscribe)
    assert_receive {:signal, %Jido.Signal{type: "agent.response.start"}}

    assert_receive {:signal,
                    %Jido.Signal{
                      type: "agent.response.chunk",
                      data: %{payload: %{chunk: "Hello"}}
                    }}

    assert_receive {:signal,
                    %Jido.Signal{
                      type: "agent.response.chunk",
                      data: %{payload: %{chunk: " World"}}
                    }}

    # Verify completion
    assert_receive {:signal,
                    %Jido.Signal{
                      type: "agent.response",
                      data: %{payload: %{content: "Hello World"}}
                    }}

    assert_receive {:signal,
                    %Jido.Signal{
                      type: "agent.turn.end",
                      data: %{payload: %{status: :success}}
                    }}

    state = :sys.get_state(pid)
    assert state.status == :idle
    # system + user + assistant
    assert length(state.llm_context.messages) == 3
  end

  test "new chat cancels in-flight loop task", %{pid: pid} do
    test_pid = self()

    stub(Response, :text, fn
      %{message: %{content: content}} when is_binary(content) -> content
      _ -> ""
    end)

    stub(Response, :tool_calls, fn _ -> [] end)

    stub(Client, :stream_chat, fn _model, context, _opts ->
      send(test_pid, {:stream_started, self()})

      receive do
        {:finish, reply_text} ->
          {:ok,
           %{
             message: %{role: "assistant", content: reply_text},
             context: ReqLLM.Context.append(context, ReqLLM.Context.assistant(reply_text))
           }}
      after
        5_000 ->
          {:error, :test_timeout}
      end
    end)

    :ok = LLMAgent.chat(pid, "Hi 1")
    assert_receive {:stream_started, stream1}, 500
    monitor1 = Process.monitor(stream1)

    :ok = LLMAgent.chat(pid, "Hi 2")
    assert_receive {:stream_started, stream2}, 2000
    refute stream1 == stream2

    assert_receive {:DOWN, ^monitor1, :process, ^stream1, _reason}, 2000

    send(stream2, {:finish, "OK 2"})

    assert_receive {:signal,
                    %Jido.Signal{
                      type: "agent.turn.end",
                      data: %{payload: %{status: :success}}
                    }},
                   1_000
  end

  test "executes tool calls", %{pid: pid} do
    # Mock Response for tool call
    stub(Response, :text, fn
      %{message: %{content: "Final Answer"}} -> "Final Answer"
      _ -> nil
    end)

    stub(Response, :tool_calls, fn
      %{message: %{tool_calls: calls}} -> calls
      _ -> []
    end)

    # Mock ReqLLM.ToolCall to handle both atom and string keys
    Mimic.copy(ReqLLM.ToolCall)
    stub(ReqLLM.ToolCall, :name, fn tc -> Map.get(tc, :name) || Map.get(tc, "name") end)

    stub(ReqLLM.ToolCall, :args_map, fn tc ->
      Map.get(tc, :arguments) || Map.get(tc, "arguments") || Map.get(tc, :args) ||
        Map.get(tc, "args")
    end)

    # Mock Client
    stub(Client, :stream_chat, fn _, context, _ ->
      # context is ReqLLM.Context, context.messages is list
      last_msg = List.last(context.messages)

      if last_msg.role == :tool do
        # Second call (after tool execution)
        {:ok,
         %{
           message: %{role: "assistant", content: "Final Answer"},
           context: ReqLLM.Context.append(context, ReqLLM.Context.assistant("Final Answer"))
         }}
      else
        # First call (tool request)
        # Use atom keys to match LLMAgent dot access (tc.id)
        tool_call = %{id: "call_1", name: "mock_tool", arguments: %{"arg" => 1}}

        {:ok,
         %{
           message: %{
             role: "assistant",
             tool_calls: [tool_call]
           },
           context:
             ReqLLM.Context.append(context, ReqLLM.Context.assistant("", tool_calls: [tool_call]))
         }}
      end
    end)

    # Mock ToolRunner
    stub(ToolRunner, :execute, fn "mock_tool", %{"arg" => 1}, _ctx ->
      {:ok, "Tool Result"}
    end)

    # Trigger chat
    :ok = LLMAgent.chat(pid, "Run tool")

    assert_receive {:signal, %Jido.Signal{type: "agent.response.start"}}
    assert_receive {:signal, %Jido.Signal{type: "tool.call.request"}}

    # Verify tool result broadcast
    assert_receive {:signal,
                    %Jido.Signal{
                      type: "tool.call.result",
                      data: %{payload: %{result: "Tool Result"}}
                    }}

    # We need to wait for the recursion to happen.
    assert_receive {:signal,
                    %Jido.Signal{
                      type: "agent.response",
                      data: %{payload: %{content: "Final Answer"}}
                    }}

    assert_receive {:signal,
                    %Jido.Signal{
                      type: "agent.turn.end",
                      data: %{payload: %{status: :success}}
                    }}
  end

  test "does not auto-accept memory proposals from unsafe sources", %{pid: pid} do
    test_pid = self()

    Mimic.copy(Cortex.Memory.Store)

    stub(Cortex.Memory.Store, :accept_proposal, fn proposal_id ->
      send(test_pid, {:accept_called, proposal_id})
      {:ok, :stubbed}
    end)

    send(
      pid,
      {:signal,
       %{
         type: "memory.proposal.created",
         data: %{
           payload: %{
             proposal_id: "p_unsafe",
             confidence: 0.95,
             content_preview: "用户偏好: 偏甜 (枫糖/蜂蜜)",
             source_signal_type: "agent.response",
             source_actor: "llm_agent"
           }
         }
       }}
    )

    refute_receive {:accept_called, _}, 200
  end

  test "auto-accepts high-confidence memory proposals sourced from user chat", %{pid: pid} do
    test_pid = self()

    Mimic.copy(Cortex.Memory.Store)

    stub(Cortex.Memory.Store, :accept_proposal, fn proposal_id ->
      send(test_pid, {:accept_called, proposal_id})
      {:ok, :stubbed}
    end)

    send(
      pid,
      {:signal,
       %{
         type: "memory.proposal.created",
         data: %{
           payload: %{
             proposal_id: "p_safe",
             confidence: 0.95,
             content_preview: "用户偏好: 偏甜 (枫糖/蜂蜜)",
             source_signal_type: "agent.chat.request",
             source_actor: "user"
           }
         }
       }}
    )

    assert_receive {:accept_called, "p_safe"}, 200
  end

  test "sandbox hook blocks path traversal", %{pid: pid} do
    stub(Response, :text, fn _ -> nil end)
    stub(Response, :tool_calls, fn _ -> [] end)

    Mimic.copy(ReqLLM.ToolCall)
    stub(ReqLLM.ToolCall, :name, fn tc -> Map.get(tc, :name) || Map.get(tc, "name") end)

    stub(ReqLLM.ToolCall, :args_map, fn tc ->
      Map.get(tc, :arguments) || Map.get(tc, "arguments") || Map.get(tc, :args) ||
        Map.get(tc, "args")
    end)

    stub(Client, :stream_chat, fn _, context, _ ->
      last_msg = List.last(context.messages)

      if last_msg.role == :tool do
        {:ok, %{message: %{role: "assistant", content: "Oops"}, context: context}}
      else
        tool_call = %{
          id: "call_bad",
          name: "write_file",
          arguments: %{"path" => "../bad.txt", "content" => "x"}
        }

        {:ok, %{message: %{role: "assistant", tool_calls: [tool_call]}, context: context}}
      end
    end)

    :ok = LLMAgent.chat(pid, "Hack system")

    assert_receive {:signal,
                    %Jido.Signal{type: "tool.call.result", data: %{payload: %{result: result}}}}

    assert result =~ "Sandbox violation"
  end

  test "permission hook requests permission and handles allowance", %{pid: pid} do
    stub(Response, :text, fn
      %{message: %{content: content}} when is_binary(content) -> content
      _ -> ""
    end)

    stub(Response, :tool_calls, fn
      %{message: %{tool_calls: calls}} -> calls
      _ -> []
    end)

    Mimic.copy(ReqLLM.ToolCall)
    stub(ReqLLM.ToolCall, :name, fn tc -> Map.get(tc, :name) || Map.get(tc, "name") end)

    stub(ReqLLM.ToolCall, :args_map, fn tc ->
      Map.get(tc, :arguments) || Map.get(tc, "arguments") || Map.get(tc, :args) ||
        Map.get(tc, "args")
    end)

    stub(Client, :stream_chat, fn _, context, _ ->
      last_msg = List.last(context.messages)

      if last_msg.role == :tool do
        {:ok, %{message: %{role: "assistant", content: "Done"}, context: context}}
      else
        tool_call = %{
          id: "call_perm",
          name: "write_file",
          arguments: %{"path" => "good.txt", "content" => "ok"}
        }

        {:ok, %{message: %{role: "assistant", tool_calls: [tool_call]}, context: context}}
      end
    end)

    stub(ToolRunner, :execute, fn "write_file", _, _ -> {:ok, "File written"} end)

    :ok = LLMAgent.chat(pid, "Write file")

    assert_receive {:signal,
                    %Jido.Signal{
                      type: "permission.request",
                      data: %{payload: %{request_id: req_id}}
                    }}

    LLMAgent.resolve_permission(pid, req_id, :allow)

    assert_receive {:signal,
                    %Jido.Signal{
                      type: "tool.call.result",
                      data: %{payload: %{result: "File written"}}
                    }}
  end
end
