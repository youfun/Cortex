# Extension Lifecycle - Unit Tests

defmodule Cortex.Extensions.ContextTest do
  use ExUnit.Case, async: true

  alias Cortex.Extensions.Context

  describe "from_agent_state/1" do
    test "builds context from agent state" do
      agent_state = %{
        session_id: "test_session",
        config: %{model: "gpt-4"},
        status: :idle,
        turn_count: 5
      }

      ctx = Context.from_agent_state(agent_state)

      assert ctx.session_id == "test_session"
      assert ctx.model == "gpt-4"
      assert ctx.status == :idle
      assert ctx.turn_count == 5
      assert ctx.channel == "agent"
    end
  end
end
