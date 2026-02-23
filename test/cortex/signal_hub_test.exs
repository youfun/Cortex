defmodule Cortex.SignalHubTest do
  use ExUnit.Case, async: false
  use Cortex.ProcessCase

  alias Cortex.SignalHub

  @valid_data %{
    provider: "test",
    event: "ping",
    action: "test",
    actor: "tester",
    origin: %{channel: "test", client: "test", platform: "server"},
    msg: "hello"
  }

  describe "emit/3" do
    test "creates and publishes a signal with payload wrapping" do
      assert {:ok, signal} = SignalHub.emit("test.ping", @valid_data)
      assert signal.type == "test.ping"
      # Verify 5-key fields are at top level of data
      assert signal.data.provider == "test"
      assert signal.data.event == "ping"
      assert signal.data.action == "test"
      assert signal.data.actor == "tester"
      assert signal.data.origin.channel == "test"
      # Verify extra fields are in payload
      assert signal.data.payload.msg == "hello"
    end

    test "uses custom source" do
      assert {:ok, signal} = SignalHub.emit("test.ping", @valid_data, source: "/test")
      assert signal.source == "/test"
    end

    test "fails if missing mandatory fields" do
      assert {:error, {:missing_fields, _}} = SignalHub.emit("test.ping", %{msg: "invalid"})
    end
  end

  describe "subscribe/2" do
    test "receives published signals matching pattern" do
      {:ok, _sub_id} = SignalHub.subscribe("test.sub.**")
      {:ok, _signal} = SignalHub.emit("test.sub.hello", Map.put(@valid_data, :value, 42))

      assert_receive {:signal, %Jido.Signal{type: "test.sub.hello"}}, 1000
    end

    test "does not receive signals not matching pattern" do
      {:ok, _sub_id} = SignalHub.subscribe("test.only.this")
      {:ok, _signal} = SignalHub.emit("test.other.topic", @valid_data)

      refute_receive {:signal, %Jido.Signal{}}, 500
    end
  end
end
