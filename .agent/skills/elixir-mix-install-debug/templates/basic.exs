#!/usr/bin/env elixir
# Purpose: [Describe what you're debugging/testing]
# Usage: elixir scripts/my_debug.exs

Mix.install([
  {:req, "~> 0.5"}
  # Add your dependencies here
  # {:my_lib, "~> 1.0"}
  # {:local_lib, path: "../path", override: true}
  # {:pr_test, github: "user/repo", branch: "feature", override: true}
])

# ============================================================================
# Load Environment Variables
# ============================================================================

defmodule DotEnv do
  @moduledoc """
  Simple .env file loader for Mix.install scripts.
  Searches for .env in current dir, parent dir, and grandparent dir.
  """

  def load(path \\ nil) do
    paths = if path, do: [path], else: [".env", "../.env", "../../.env"]
    
    case Enum.find(paths, &File.exists?/1) do
      nil ->
        IO.puts("⚠️  No .env file found in: #{inspect(paths)}")
        IO.puts("   Continuing with existing environment variables...")
        
      found_path ->
        IO.puts("✅ Loading environment from: #{Path.expand(found_path)}")
        parse_and_load(found_path)
    end
  end

  defp parse_and_load(path) do
    File.read!(path)
    |> String.split("\n")
    |> Enum.each(fn line ->
      line = String.trim(line)
      
      unless line == "" or String.starts_with?(line, "#") do
        case String.split(line, "=", parts: 2) do
          [key, value] ->
            value = value
              |> String.trim()
              |> String.trim_leading("\"")
              |> String.trim_trailing("\"")
              |> String.trim_leading("'")
              |> String.trim_trailing("'")
            
            System.put_env(String.trim(key), value)
          
          _ -> :ok
        end
      end
    end)
  end
end

DotEnv.load()

# ============================================================================
# Configuration
# ============================================================================

config = %{
  api_key: System.get_env("API_KEY"),
  endpoint: System.get_env("API_ENDPOINT") || "https://api.example.com"
  # Add your config here
}

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("  Configuration")
IO.puts(String.duplicate("=", 60) <> "\n")
IO.inspect(config, pretty: true, label: "Config")

# Validate required config
if is_nil(config.api_key) do
  IO.puts("\n❌ ERROR: API_KEY not found in environment")
  IO.puts("   Please set it in .env file or export it")
  System.halt(1)
end

# ============================================================================
# Test 1: [Describe what this tests]
# ============================================================================

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("  Test 1: Basic Request")
IO.puts(String.duplicate("=", 60) <> "\n")

case Req.get(config.endpoint, headers: [{"authorization", "Bearer #{config.api_key}"}]) do
  {:ok, %{status: 200, body: body}} ->
    IO.puts("✅ Success!")
    IO.inspect(body, label: "Response", limit: 5)
    
  {:ok, %{status: status, body: body}} ->
    IO.puts("❌ Failed with status: #{status}")
    IO.inspect(body, label: "Error Response")
    
  {:error, reason} ->
    IO.puts("❌ Request failed")
    IO.inspect(reason, label: "Error")
end

# ============================================================================
# Test 2: [Describe what this tests]
# ============================================================================

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("  Test 2: [Your test description]")
IO.puts(String.duplicate("=", 60) <> "\n")

# Add your test code here
# Example:
# result = some_function()
# IO.inspect(result, label: "Result")

# ============================================================================
# Summary
# ============================================================================

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("  Tests Complete")
IO.puts(String.duplicate("=", 60) <> "\n")
