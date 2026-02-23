defmodule Cortex.Session.FactoryTest do
  use Cortex.DataCase, async: true

  alias Cortex.Session.Factory

  describe "build_opts/1" do
    test "uses provided options" do
      opts =
        Factory.build_opts(
          session_id: "session_1",
          model: "model-a",
          workspace_id: "workspace-1"
        )

      assert opts[:session_id] == "session_1"
      assert opts[:model] == "model-a"
      assert opts[:workspace_id] == "workspace-1"
    end

    test "uses default model when missing" do
      opts = Factory.build_opts(session_id: "session_2")

      assert opts[:session_id] == "session_2"
      assert is_binary(opts[:model])
      assert opts[:model] != ""
      refute Keyword.has_key?(opts, :workspace_id)
    end

    test "requires session_id" do
      assert_raise KeyError, fn -> Factory.build_opts([]) end
    end
  end
end
