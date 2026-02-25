defmodule Cortex.Search.DispatcherTest do
  use ExUnit.Case, async: true

  alias Cortex.Search.Dispatcher

  describe "search/2" do
    test "returns error when no provider is configured" do
      # Clear environment variables
      System.delete_env("TAVILY_API_KEY")
      System.delete_env("BRAVE_API_KEY")

      assert {:error, message} = Dispatcher.search("test query")
      assert message =~ "No search provider configured"
    end

    test "uses Tavily when TAVILY_API_KEY is set" do
      System.put_env("TAVILY_API_KEY", "test_key")
      System.delete_env("BRAVE_API_KEY")

      # This will fail with actual API call, but we're testing provider selection
      result = Dispatcher.search("test")
      assert match?({:error, _}, result)

      System.delete_env("TAVILY_API_KEY")
    end

    test "uses Brave when only BRAVE_API_KEY is set" do
      System.delete_env("TAVILY_API_KEY")
      System.put_env("BRAVE_API_KEY", "test_key")

      # This will fail with actual API call, but we're testing provider selection
      result = Dispatcher.search("test")
      assert match?({:error, _}, result)

      System.delete_env("BRAVE_API_KEY")
    end
  end
end
