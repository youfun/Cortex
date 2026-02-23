defmodule Cortex.ConfigTest do
  use Cortex.DataCase

  alias Cortex.Config

  describe "llm_models" do
    alias Cortex.Config.LlmModel

    import Cortex.ConfigFixtures

    @invalid_attrs %{
      enabled: nil,
      name: nil,
      status: nil,
      source: nil,
      adapter: nil,
      display_name: nil,
      provider_drive: nil,
      context_window: nil,
      capabilities: nil,
      pricing: nil,
      architecture: nil,
      custom_overrides: nil
    }

    test "list_llm_models/0 returns all llm_models" do
      llm_model = llm_model_fixture()
      assert Config.list_llm_models() == [llm_model]
    end

    test "get_llm_model!/1 returns the llm_model with given id" do
      llm_model = llm_model_fixture()
      assert Config.get_llm_model!(llm_model.id) == llm_model
    end

    test "create_llm_model/1 with valid data creates a llm_model" do
      valid_attrs = %{
        enabled: true,
        name: "gpt-4o",
        status: "active",
        source: "seed",
        adapter: "openai",
        display_name: "GPT-4o",
        provider_drive: "openai",
        context_window: 128_000,
        capabilities: %{"vision" => true},
        pricing: %{"input" => 2.5, "output" => 10.0},
        architecture: %{"input_modalities" => ["text"]},
        custom_overrides: %{},
        api_key: "sk-proj-test",
        base_url: "https://api.openai.com/v1"
      }

      assert {:ok, %LlmModel{} = llm_model} = Config.create_llm_model(valid_attrs)
      assert llm_model.enabled == true
      assert llm_model.name == "gpt-4o"
      assert llm_model.status == "active"
      assert llm_model.source == "seed"
      assert llm_model.adapter == "openai"
      assert llm_model.display_name == "GPT-4o"
      assert llm_model.provider_drive == "openai"
      assert llm_model.context_window == 128_000
      assert llm_model.capabilities == %{"vision" => true}
      assert llm_model.pricing == %{"input" => 2.5, "output" => 10.0}
      assert llm_model.architecture == %{"input_modalities" => ["text"]}
      assert llm_model.custom_overrides == %{}
      assert llm_model.api_key == "sk-proj-test"
      assert llm_model.base_url == "https://api.openai.com/v1"
    end

    test "create_llm_model/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Config.create_llm_model(@invalid_attrs)
    end

    test "update_llm_model/2 with valid data updates the llm_model" do
      llm_model = llm_model_fixture()

      update_attrs = %{
        enabled: false,
        name: "claude-3-opus",
        status: "beta",
        source: "llmdb",
        adapter: "anthropic",
        display_name: "Claude 3 Opus",
        provider_drive: "anthropic",
        context_window: 200_000,
        capabilities: %{"thinking" => true},
        pricing: %{"input" => 15.0, "output" => 75.0},
        architecture: %{"max_output_tokens" => 4096},
        custom_overrides: %{},
        api_key: "sk-ant-test",
        base_url: "https://api.anthropic.com"
      }

      assert {:ok, %LlmModel{} = llm_model} = Config.update_llm_model(llm_model, update_attrs)
      assert llm_model.enabled == false
      assert llm_model.name == "claude-3-opus"
      assert llm_model.status == "beta"
      assert llm_model.source == "llmdb"
      assert llm_model.adapter == "anthropic"
      assert llm_model.display_name == "Claude 3 Opus"
      assert llm_model.provider_drive == "anthropic"
      assert llm_model.context_window == 200_000
      assert llm_model.capabilities == %{"thinking" => true}
      assert llm_model.pricing == %{"input" => 15.0, "output" => 75.0}
      assert llm_model.architecture == %{"max_output_tokens" => 4096}
      assert llm_model.custom_overrides == %{}
      assert llm_model.api_key == "sk-ant-test"
      assert llm_model.base_url == "https://api.anthropic.com"
    end

    test "update_llm_model/2 with invalid data returns error changeset" do
      llm_model = llm_model_fixture()
      assert {:error, %Ecto.Changeset{}} = Config.update_llm_model(llm_model, @invalid_attrs)
      assert llm_model == Config.get_llm_model!(llm_model.id)
    end

    test "delete_llm_model/1 deletes the llm_model" do
      llm_model = llm_model_fixture()
      assert {:ok, %LlmModel{}} = Config.delete_llm_model(llm_model)
      assert_raise Ecto.NoResultsError, fn -> Config.get_llm_model!(llm_model.id) end
    end

    test "change_llm_model/1 returns a llm_model changeset" do
      llm_model = llm_model_fixture()
      assert %Ecto.Changeset{} = Config.change_llm_model(llm_model)
    end
  end
end
