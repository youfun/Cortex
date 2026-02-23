defmodule Cortex.LLM.ConfigTest do
  use Cortex.DataCase

  alias Cortex.LLM.Config, as: LLMConfig
  alias Cortex.Config
  alias Cortex.Config.Metadata

  describe "get/1" do
    setup do
      {:ok, model} =
        Config.create_llm_model(%{
          name: "test-gpt-4",
          display_name: "Test GPT-4",
          provider_drive: "openai",
          adapter: "openai",
          source: "seed",
          enabled: true,
          context_window: 128_000,
          capabilities: %{"vision" => true},
          pricing: %{"input" => 2.5, "output" => 10.0},
          architecture: %{"max_output_tokens" => 4096},
          api_key: "sk-test-key-123",
          base_url: "https://api.openai.com/v1"
        })

      Metadata.reload()

      %{model: model}
    end

    test "returns valid config for existing model", %{model: model} do
      assert {:ok, model_spec, req_opts} = LLMConfig.get(model.name)

      assert model_spec == "openai:test-gpt-4"
      assert Keyword.get(req_opts, :api_key) == "sk-test-key-123"
      assert Keyword.get(req_opts, :base_url) == "https://api.openai.com/v1"
    end

    test "returns error for non-existent model" do
      assert {:error, :model_not_found} = LLMConfig.get("non-existent-model")
    end

    test "respects custom_overrides", %{model: model} do
      {:ok, model} =
        Config.update_llm_model(model, %{
          custom_overrides: %{"temperature" => 0.1, "max_retries" => 5}
        })

      Metadata.reload()

      assert {:ok, _model_spec, req_opts} = LLMConfig.get(model.name)
      assert Keyword.get(req_opts, :temperature) == 0.1
      assert Keyword.get(req_opts, :max_retries) == 5
    end
  end

  describe "get_model/1" do
    test "retrieves model from metadata cache" do
      {:ok, model} =
        Config.create_llm_model(%{
          name: "cached-test-model",
          provider_drive: "openai",
          adapter: "openai",
          source: "seed",
          enabled: true
        })

      Metadata.reload()

      assert {:ok, cached_model} = LLMConfig.get_model(model.name)
      assert cached_model.name == model.name
    end

    test "returns error for non-existent model" do
      assert {:error, :model_not_found} = LLMConfig.get_model("does-not-exist")
    end
  end
end
