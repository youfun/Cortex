defmodule Cortex.SignalHubTraceTest do
  use ExUnit.Case

  alias Jido.Signal.{Trace, TraceContext}
  alias Cortex.SignalHub

  setup do
    # Clear any trace context before each test
    TraceContext.clear()
    :ok
  end

  test "emit without trace context preserves signal" do
    data = %{
      provider: "test",
      event: "test",
      action: "emit",
      actor: "test",
      origin: %{channel: "test", client: "test", platform: "test"}
    }

    {:ok, signal} = SignalHub.emit("test.untraced", data)

    assert Trace.get(signal) == nil
  end

  test "emit propagates current trace context" do
    # Setup root trace
    root_ctx = Trace.new_root()
    TraceContext.set(root_ctx)

    data = %{
      provider: "test",
      event: "test",
      action: "emit",
      actor: "test",
      origin: %{channel: "test", client: "test", platform: "test"}
    }

    {:ok, signal} = SignalHub.emit("test.traced", data)

    # Verify signal carries trace info
    signal_ctx = Trace.get(signal)
    assert signal_ctx != nil
    assert signal_ctx.trace_id == root_ctx.trace_id
    assert signal_ctx.parent_span_id == root_ctx.span_id
  end

  test "emit respects explicit causation_id" do
    causation_id = "some-causal-id"

    data = %{
      provider: "test",
      event: "test",
      action: "emit",
      actor: "test",
      origin: %{channel: "test", client: "test", platform: "test"}
    }

    {:ok, signal} = SignalHub.emit("test.causal", data, causation_id: causation_id)

    # Verify signal carries trace info with causation_id
    signal_ctx = Trace.get(signal)
    assert signal_ctx != nil
    assert signal_ctx.causation_id == causation_id
  end
end
