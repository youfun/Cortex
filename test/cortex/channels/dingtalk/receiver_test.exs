defmodule Cortex.Channels.Dingtalk.ReceiverTest do
  use ExUnit.Case
  alias Cortex.Channels.Dingtalk.Receiver

  test "module exists" do
    assert Code.ensure_loaded?(Receiver)
  end

  # Due to WebSockex being a process that connects on start,
  # unit testing without mocking the network or WebSockex itself is hard.
  # We verify the module structure and basic logic functions if exposed.
  # Since logic is private, we rely on integration or end-to-end tests later.
end
