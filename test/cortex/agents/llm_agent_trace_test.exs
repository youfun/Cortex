defmodule Cortex.Agents.LLMAgentTraceTest do
  use Cortex.DataCase, async: false
  use Mimic

  alias Cortex.Agents.LLMAgent
  alias Cortex.LLM.Client
  alias Jido.Signal.{Trace, TraceContext}
  alias Cortex.SignalHub
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
    conversation_id = String.replace(session_id, "session_", "")

    %Cortex.Conversations.Conversation{
      id: conversation_id,
      title: "Trace Test",
      status: "active"
    }
    |> Cortex.Repo.insert!()

    Phoenix.PubSub.subscribe(Cortex.PubSub, "jido.studio.session:#{session_id}")
    Cortex.SignalHub.subscribe("**")

    {:ok, pid} = LLMAgent.start_link(session_id: session_id)
    Cortex.DataCase.allow_process(owner_pid, pid)
    %{pid: pid, session_id: session_id}
  end

  test "agent establishes trace context from incoming signal", %{pid: pid, session_id: session_id} do
    # 1. Create a root trace and set it in current process
    root_ctx = Trace.new_root()
    TraceContext.set(root_ctx)

    # 2. Create a signal carrying this trace
    data = %{
      session_id: session_id,
      content: "Hello Tracing",
      # Normalized structure
      payload: %{session_id: session_id, content: "Hello Tracing"}
    }

    {:ok, signal} = Jido.Signal.new("agent.chat.request", data)

    # Inject trace into signal (simulating external trace)
    {:ok, traced_signal} = TraceContext.propagate_to(signal, "external-trigger-id")

    # Clear context so we don't pollute subsequent tests or checks
    TraceContext.clear()

    # 3. Mock Client to return immediately so we get a response
    stub(Response, :text, fn _ -> "Response" end)
    stub(Response, :tool_calls, fn _ -> [] end)

    stub(Client, :stream_chat, fn _model, context, opts ->
      if on_chunk = opts[:on_chunk], do: on_chunk.("Response")
      {:ok, %{message: %{role: "assistant", content: "Response"}, context: context}}
    end)

    # 4. Send signal directly to agent (simulate SignalHub dispatch)
    send(pid, {:signal, traced_signal})

    # 5. Verify agent emits response with same trace ID
    assert_receive {:signal, %Jido.Signal{type: "agent.response.start"} = response_signal}, 1000

    response_ctx = Trace.get(response_signal)

    # If Trace.get fails, check extensions directly (fallback for test robustness)
    if response_ctx == nil do
      correlation =
        response_signal.extensions["correlation"] || response_signal.extensions[:correlation]

      assert correlation != nil, "Signal missing correlation extension"
      assert correlation.trace_id == root_ctx.trace_id

      traced_signal_ctx = Trace.get(traced_signal)
      # assert correlation.parent_span_id == traced_signal_ctx.span_id
      assert correlation.parent_span_id == traced_signal_ctx.span_id
    else
      assert response_ctx.trace_id == root_ctx.trace_id
      assert response_ctx.span_id != root_ctx.span_id

      traced_signal_ctx = Trace.get(traced_signal)
      assert response_ctx.parent_span_id == traced_signal_ctx.span_id
    end
  end

  test "agent propagates trace to tool execution", %{pid: pid, session_id: session_id} do
    # 1. Create a root trace and set it in current process
    root_ctx = Trace.new_root()
    TraceContext.set(root_ctx)

    # 2. Create a signal carrying this trace
    data = %{
      session_id: session_id,
      content: "Use tool",
      payload: %{session_id: session_id, content: "Use tool"}
    }

    {:ok, signal} = Jido.Signal.new("agent.chat.request", data)
    {:ok, traced_signal} = TraceContext.propagate_to(signal, "external-trigger-id")
    TraceContext.clear()

    # 3. Mock Tool Call flow
    stub(Response, :text, fn _ -> nil end)

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

    stub(Cortex.Tools.ToolRunner, :execute, fn "mock_tool", _, _ -> {:ok, "Result"} end)

    stub(Client, :stream_chat, fn _, context, _ ->
      last_msg = List.last(context.messages)

      if last_msg.role == :tool do
        {:ok, %{message: %{role: "assistant", content: "Done"}, context: context}}
      else
        tool_call = %{id: "call_1", name: "mock_tool", arguments: %{"arg" => 1}}
        {:ok, %{message: %{role: "assistant", tool_calls: [tool_call]}, context: context}}
      end
    end)

    # 4. Send signal
    send(pid, {:signal, traced_signal})

    # 5. Verify tool.call.request has trace info
    # This signal is emitted by the Task, so if it has trace info, propagation worked.
    assert_receive {:signal, %Jido.Signal{type: "tool.call.request"} = tool_signal}, 1000

    tool_ctx = Trace.get(tool_signal)

    if tool_ctx == nil do
      correlation = tool_signal.extensions["correlation"] || tool_signal.extensions[:correlation]
      assert correlation != nil, "Tool signal missing correlation extension"
      assert correlation.trace_id == root_ctx.trace_id
    else
      assert tool_ctx.trace_id == root_ctx.trace_id
      # Parent span should be the span from agent process (which is child of root trace)
      # But exact span hierarchy is:
      # Root (External) -> Agent Span (via ensure_from_signal) -> Tool Span (via emit)

      # Agent Span ID is what's in TraceContext.current() in Agent process.
      # We can't easily assert on parent_span_id value without knowing Agent Span ID.
      # But we can check that span_id exists and is different from root.
      assert tool_ctx.span_id != nil
    end
  end
end
