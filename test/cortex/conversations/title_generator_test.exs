defmodule Cortex.Conversations.TitleGeneratorTest do
  use Cortex.DataCase, async: true

  alias Cortex.Config.Settings
  alias Cortex.Conversations
  alias Cortex.Conversations.TitleGenerator
  alias Cortex.Workspaces

  setup do
    workspace = Workspaces.ensure_default_workspace()
    {:ok, conversation} = Conversations.create_conversation(%{title: "Test"}, workspace.id)
    %{conversation: conversation}
  end

  describe "maybe_generate/3" do
    test "skips when title generation is disabled", %{conversation: conv} do
      Settings.set_title_generation("disabled")
      assert :skip = TitleGenerator.maybe_generate(conv.id, "Hello", "gemini-3-flash")
    end

    test "triggers async generation when enabled", %{conversation: conv} do
      Settings.set_title_generation("conversation")
      result = TitleGenerator.maybe_generate(conv.id, "Hello", "gemini-3-flash")
      assert {:ok, _pid} = result
    end
  end
end
