defmodule Cortex.Config.SettingsTest do
  use Cortex.DataCase

  alias Cortex.Config.Settings
  alias Cortex.Config

  describe "default model management" do
    test "get_skill_default_model/0 returns default when not configured" do
      assert Settings.get_skill_default_model() == "gemini-3-flash"
    end

    test "set_skill_default_model/1 updates the default model" do
      assert {:ok, "claude-3-5-sonnet-20241022"} =
               Settings.set_skill_default_model("claude-3-5-sonnet-20241022")

      assert Settings.get_skill_default_model() == "claude-3-5-sonnet-20241022"
    end

    test "get_effective_skill_default_model/0 returns first available model when default unavailable" do
      {:ok, _model} =
        Config.create_llm_model(%{
          name: "test-model",
          provider_drive: "openai",
          adapter: "openai",
          source: "seed",
          enabled: true
        })

      result = Settings.get_effective_skill_default_model()
      assert is_binary(result)
    end
  end

  describe "model management" do
    setup do
      {:ok, model} =
        Config.create_llm_model(%{
          name: "test-model",
          provider_drive: "openai",
          adapter: "openai",
          source: "seed",
          enabled: false
        })

      %{model: model}
    end

    test "enable_model/1 enables a model", %{model: model} do
      assert {:ok, updated} = Settings.enable_model(model.name)
      assert updated.enabled == true
    end

    test "disable_model/1 disables a model", %{model: model} do
      {:ok, _} = Settings.enable_model(model.name)
      assert {:ok, updated} = Settings.disable_model(model.name)
      assert updated.enabled == false
    end

    test "model_available?/1 checks model status", %{model: model} do
      assert Settings.model_available?(model.name) == false
      Settings.enable_model(model.name)
      assert Settings.model_available?(model.name) == true
    end

    test "list_available_models/0 returns enabled models" do
      Config.create_llm_model(%{
        name: "available-model",
        provider_drive: "openai",
        adapter: "openai",
        source: "seed",
        enabled: true
      })

      Config.create_llm_model(%{
        name: "unavailable-model",
        provider_drive: "anthropic",
        adapter: "anthropic",
        source: "seed",
        enabled: false
      })

      available = Settings.list_available_models()
      available_names = Enum.map(available, & &1.name)

      assert "available-model" in available_names
      refute "unavailable-model" in available_names
    end
  end
end
