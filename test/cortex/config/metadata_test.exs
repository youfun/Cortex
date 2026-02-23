defmodule Cortex.Config.MetadataTest do
  use Cortex.DataCase

  alias Cortex.Config.Metadata
  alias Cortex.Config

  describe "cache management" do
    test "reload/0 loads models into cache" do
      {:ok, _model} =
        Config.create_llm_model(%{
          name: "test-model",
          provider_drive: "openai",
          adapter: "openai",
          source: "seed",
          enabled: true
        })

      assert :ok = Metadata.reload()
      assert Metadata.get_all_models() != []
    end

    test "get_model/1 retrieves model from cache" do
      {:ok, model} =
        Config.create_llm_model(%{
          name: "cached-model",
          provider_drive: "openai",
          adapter: "openai",
          source: "seed",
          enabled: true
        })

      Metadata.reload()
      cached = Metadata.get_model("cached-model")

      assert cached != nil
      assert cached.name == model.name
    end

    test "get_all_models/0 returns all cached models" do
      Metadata.reload()
      models = Metadata.get_all_models()
      assert is_list(models)
    end

    test "get_available_models/0 filters enabled models" do
      Config.create_llm_model(%{
        name: "available-model",
        provider_drive: "openai",
        adapter: "openai",
        source: "seed",
        enabled: true
      })

      Config.create_llm_model(%{
        name: "disabled-model",
        provider_drive: "openai",
        adapter: "openai",
        source: "seed",
        enabled: false
      })

      Metadata.reload()
      available = Metadata.get_available_models()
      available_names = Enum.map(available, & &1.name)

      assert "available-model" in available_names
      refute "disabled-model" in available_names
    end
  end

  describe "seed data loading" do
    test "load_seeds/0 creates default models" do
      # 清空数据库
      Repo.delete_all(Config.LlmModel)

      # 加载种子数据
      Metadata.load_seeds()

      # 验证 models
      models = Config.list_llm_models()
      model_names = Enum.map(models, & &1.name)

      assert "openai" in model_names
      assert "anthropic" in model_names
      assert "google" in model_names
      assert "ollama" in model_names
    end
  end

  describe "LLMDB sync" do
    test "sync_from_llmdb/2 creates new models" do
      llmdb_models = [
        %{
          "name" => "new-llmdb-model",
          "provider_drive" => "test_sync",
          "adapter" => "openai",
          "source" => "llmdb",
          "status" => "active",
          "enabled" => true
        }
      ]

      Metadata.sync_from_llmdb("test_sync", llmdb_models)

      model = Config.get_llm_model_by_name("new-llmdb-model")
      assert model != nil
      assert model.source == "llmdb"
    end

    test "sync_from_llmdb/2 preserves custom models" do
      {:ok, _custom_model} =
        Config.create_llm_model(%{
          name: "custom-model",
          provider_drive: "openai",
          adapter: "openai",
          source: "custom",
          enabled: true,
          custom_overrides: %{"context_window" => 999_999}
        })

      llmdb_models = [
        %{
          "name" => "custom-model",
          "provider_drive" => "openai",
          "adapter" => "openai",
          "source" => "llmdb",
          "context_window" => 8192,
          "enabled" => false
        }
      ]

      Metadata.sync_from_llmdb("openai", llmdb_models)

      updated = Config.get_llm_model_by_name("custom-model")
      assert updated.source == "custom"
    end
  end
end
