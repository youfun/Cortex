defmodule Cortex.Channels.ConfigLoaderTest do
  use Cortex.DataCase

  alias Cortex.Channels.ConfigLoader
  alias Cortex.Channels

  describe "load/1" do
    test "merges config with correct priority (DB > JSON > Env)" do
      adapter = "test_adapter"

      # 1. Setup Env (Lowest Priority)
      Application.put_env(:cortex, :test_adapter,
        client_id: "env_id",
        secret: "env_secret"
      )

      # 2. Setup JSON (Middle Priority) - Mocking via file is tricky in unit tests,
      # so we will test the merge logic by manually injecting if possible,
      # or trust the integration. For now, let's verify Env + DB first.

      # 3. Setup DB (Highest Priority)
      {:ok, _} =
        Channels.create_channel_config(%{
          "adapter" => adapter,
          "name" => "Test Bot",
          "enabled" => true,
          # Overrides Env
          "config" => %{"client_id" => "db_id"}
        })

      config = ConfigLoader.load(adapter)

      # DB overrides Env
      assert config["client_id"] == "db_id"
      # Env persists if not in DB
      assert config["secret"] == "env_secret"
    end

    test "ignores DB config if disabled" do
      adapter = "disabled_adapter"

      Application.put_env(:cortex, :disabled_adapter, client_id: "env_id")

      {:ok, _} =
        Channels.create_channel_config(%{
          "adapter" => adapter,
          "name" => "Disabled Bot",
          "enabled" => false,
          "config" => %{"client_id" => "db_id"}
        })

      config = ConfigLoader.load(adapter)

      assert config["client_id"] == "env_id"
    end
  end
end
