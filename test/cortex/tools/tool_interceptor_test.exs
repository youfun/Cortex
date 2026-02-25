defmodule Cortex.Tools.ToolInterceptorTest do
  use Cortex.DataCase, async: true

  alias Cortex.Tools.ToolInterceptor

  describe "check/3" do
    test "allows non-config tools without approval" do
      assert :ok = ToolInterceptor.check("read_file", %{path: "/test"}, %{})
      assert :ok = ToolInterceptor.check("shell", %{command: "ls"}, %{})
    end

    test "requires approval for config tools" do
      assert {:approval_required, reason} = ToolInterceptor.check("update_search_config", %{}, %{})
      assert reason =~ "requires user approval"

      assert {:approval_required, _} = ToolInterceptor.check("update_model_config", %{}, %{})
      assert {:approval_required, _} = ToolInterceptor.check("update_channel_config", %{}, %{})
    end

    test "allows config tools when pre-approved" do
      ctx = %{approved_tools: ["update_search_config"]}
      assert :ok = ToolInterceptor.check("update_search_config", %{}, ctx)
    end
  end
end
