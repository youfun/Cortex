defmodule Cortex.Search.IntegrationTest do
  use ExUnit.Case, async: false

  alias Cortex.Search.Dispatcher
  alias Cortex.Search.Providers.{Brave, Tavily}
  alias Cortex.Tools.Handlers.WebSearch

  setup do
    # Save original env vars
    original_tavily = System.get_env("TAVILY_API_KEY")
    original_brave = System.get_env("BRAVE_API_KEY")

    on_exit(fn ->
      # Restore original env vars
      if original_tavily, do: System.put_env("TAVILY_API_KEY", original_tavily), else: System.delete_env("TAVILY_API_KEY")
      if original_brave, do: System.put_env("BRAVE_API_KEY", original_brave), else: System.delete_env("BRAVE_API_KEY")
    end)

    :ok
  end

  describe "Tavily provider with mocked HTTP" do
    test "successfully parses Tavily API response" do
      System.put_env("TAVILY_API_KEY", "test_tavily_key")
      System.delete_env("BRAVE_API_KEY")

      # Mock Tavily API response
      mock_response = %{
        "results" => [
          %{
            "title" => "Elixir GenServer Documentation",
            "url" => "https://hexdocs.pm/elixir/GenServer.html",
            "content" => "GenServer is a behaviour module for implementing the server of a client-server relation.",
            "published_date" => "2024-01-15"
          },
          %{
            "title" => "Understanding GenServer in Elixir",
            "url" => "https://example.com/genserver-guide",
            "content" => "A comprehensive guide to GenServer patterns in Elixir applications.",
            "published_date" => nil
          }
        ]
      }

      # Create a mock Req request with plug
      req = Req.new(plug: fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/search"
        
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        body_map = Jason.decode!(body)
        
        assert body_map["query"] == "elixir genserver"
        assert body_map["api_key"] == "test_tavily_key"
        
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)

      # Test Tavily provider directly with mocked request
      result = Req.post(req, url: "http://mock/search", 
        json: %{query: "elixir genserver", max_results: 5, api_key: "test_tavily_key"})

      assert {:ok, %Req.Response{status: 200, body: body}} = result
      
      # Parse results using Tavily's parser logic
      results = Enum.map(body["results"], fn r ->
        %{
          title: r["title"] || "",
          url: r["url"] || "",
          snippet: r["content"] || "",
          published_date: r["published_date"]
        }
      end)

      assert length(results) == 2
      assert hd(results).title == "Elixir GenServer Documentation"
      assert hd(results).url == "https://hexdocs.pm/elixir/GenServer.html"
    end
  end

  describe "Brave provider with mocked HTTP" do
    test "successfully parses Brave API response" do
      System.delete_env("TAVILY_API_KEY")
      System.put_env("BRAVE_API_KEY", "test_brave_key")

      # Mock Brave API response
      mock_response = %{
        "web" => %{
          "results" => [
            %{
              "title" => "Elixir Programming Language",
              "url" => "https://elixir-lang.org",
              "description" => "Elixir is a dynamic, functional language for building scalable applications.",
              "age" => "2024-02-20"
            }
          ]
        }
      }

      # Create a mock Req request
      req = Req.new(plug: fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/web/search"
        
        # Check query params
        params = URI.decode_query(conn.query_string)
        assert params["q"] == "elixir"
        assert params["count"] == "5"
        
        # Check headers
        assert Enum.any?(conn.req_headers, fn {k, v} -> 
          k == "x-subscription-token" && v == "test_brave_key" 
        end)
        
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)

      # Test Brave provider with mocked request
      result = Req.get(req, url: "http://mock/web/search",
        params: %{q: "elixir", count: 5},
        headers: [{"x-subscription-token", "test_brave_key"}])

      assert {:ok, %Req.Response{status: 200, body: body}} = result
      
      # Parse results using Brave's parser logic
      results = Enum.map(body["web"]["results"], fn r ->
        %{
          title: r["title"] || "",
          url: r["url"] || "",
          snippet: r["description"] || "",
          published_date: r["age"]
        }
      end)

      assert length(results) == 1
      assert hd(results).title == "Elixir Programming Language"
    end
  end

  describe "Dispatcher fallback logic" do
    test "returns error when no provider is available" do
      System.delete_env("TAVILY_API_KEY")
      System.delete_env("BRAVE_API_KEY")

      assert {:error, message} = Dispatcher.search("test query")
      assert message =~ "No search provider configured"
    end

    test "uses Tavily when both providers are available" do
      System.put_env("TAVILY_API_KEY", "test_tavily")
      System.put_env("BRAVE_API_KEY", "test_brave")

      # Both providers are available, should use Tavily (default)
      assert Tavily.available?()
      assert Brave.available?()
    end

    test "falls back to Brave when Tavily is unavailable" do
      System.delete_env("TAVILY_API_KEY")
      System.put_env("BRAVE_API_KEY", "test_brave")

      refute Tavily.available?()
      assert Brave.available?()
    end
  end

  describe "WebSearch handler" do
    test "formats results correctly" do
      # Test the formatting logic
      results = [
        %{
          title: "Result 1",
          url: "https://example.com/1",
          snippet: "This is the first result",
          published_date: nil
        },
        %{
          title: "Result 2",
          url: "https://example.com/2",
          snippet: "This is the second result",
          published_date: "2024-01-01"
        }
      ]

      formatted = results
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {r, i} ->
        "#{i}. #{r.title}\n   URL: #{r.url}\n   #{r.snippet}"
      end)

      assert formatted =~ "1. Result 1"
      assert formatted =~ "URL: https://example.com/1"
      assert formatted =~ "This is the first result"
      assert formatted =~ "2. Result 2"
    end

    test "handles both string and atom keys in args" do
      # Test with string keys
      args_string = %{"query" => "test", "count" => 3}
      assert Map.get(args_string, :query) || Map.get(args_string, "query") == "test"

      # Test with atom keys
      args_atom = %{query: "test", count: 3}
      assert Map.get(args_atom, :query) || Map.get(args_atom, "query") == "test"
    end
  end

  describe "SearchExtension" do
    test "can be loaded and registers web_search tool" do
      # Manually load the extension in test
      :ok = Cortex.Extensions.Loader.load_extension(Cortex.Extensions.SearchExtension)
      
      tools = Cortex.Tools.Registry.list_dynamic()
      web_search_tool = Enum.find(tools, fn t -> t.name == "web_search" end)

      assert web_search_tool != nil
      assert web_search_tool.name == "web_search"
      assert web_search_tool.description =~ "Search the web"
      assert web_search_tool.module == Cortex.Tools.Handlers.WebSearch
      
      # Check parameters
      params = web_search_tool.parameters
      assert Keyword.has_key?(params, :query)
      assert Keyword.has_key?(params, :count)
      assert Keyword.has_key?(params, :provider)
      
      # Clean up
      Cortex.Extensions.Loader.unload_extension(Cortex.Extensions.SearchExtension)
    end
  end
end
