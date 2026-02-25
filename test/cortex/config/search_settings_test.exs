defmodule Cortex.Config.SearchSettingsTest do
  use Cortex.DataCase, async: true

  alias Cortex.Config.SearchSettings

  setup do
    # Clear persistent_term cache between tests
    :persistent_term.erase({SearchSettings, :cached})
    :ok
  end

  describe "get_settings/0" do
    test "returns default settings when none exist" do
      settings = SearchSettings.get_settings()
      assert settings.default_provider == "tavily"
      assert settings.enable_llm_title_generation == false
    end
  end

  describe "update_settings/1" do
    test "creates new settings" do
      attrs = %{
        default_provider: "brave",
        brave_api_key: "test_key",
        enable_llm_title_generation: true
      }

      assert {:ok, settings} = SearchSettings.update_settings(attrs)
      assert settings.default_provider == "brave"
      assert settings.brave_api_key == "test_key"
      assert settings.enable_llm_title_generation == true
    end

    test "updates existing settings" do
      {:ok, _} = SearchSettings.update_settings(%{default_provider: "tavily"})
      {:ok, updated} = SearchSettings.update_settings(%{default_provider: "brave"})

      assert updated.default_provider == "brave"
    end

    test "validates provider" do
      assert {:error, changeset} = SearchSettings.update_settings(%{default_provider: "invalid"})
      assert changeset.errors[:default_provider]
    end
  end
end
