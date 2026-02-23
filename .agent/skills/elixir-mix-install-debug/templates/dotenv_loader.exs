#!/usr/bin/env elixir
# Standalone DotEnv module for Mix.install scripts
# Copy this module into your debug script to load .env files

defmodule DotEnv do
  @moduledoc """
  Simple .env file loader for Mix.install scripts.
  
  Searches for .env in current directory, parent, and grandparent.
  Gracefully handles missing files.
  
  ## Usage
  
      DotEnv.load()  # Search default paths
      DotEnv.load(".env.test")  # Specific file
      
      # Then access variables
      api_key = System.get_env("API_KEY")
  """

  @doc """
  Load environment variables from .env file.
  
  If `path` is provided, only that file is checked.
  Otherwise, searches [".env", "../.env", "../../.env"] in order.
  """
  def load(path \\ nil) do
    paths = if path, do: [path], else: [".env", "../.env", "../../.env"]
    
    case Enum.find(paths, &File.exists?/1) do
      nil ->
        IO.puts("⚠️  No .env file found in: #{inspect(paths)}")
        IO.puts("   Continuing with existing environment variables...")
        :not_found
        
      found_path ->
        IO.puts("✅ Loading environment from: #{Path.expand(found_path)}")
        parse_and_load(found_path)
        :ok
    end
  end

  @doc """
  Load with explicit error on missing file.
  
  Raises if file not found. Use when .env is required.
  """
  def load!(path \\ ".env") do
    unless File.exists?(path) do
      raise "Required .env file not found: #{path}"
    end
    
    parse_and_load(path)
    :ok
  end

  defp parse_and_load(path) do
    File.read!(path)
    |> String.split("\n")
    |> Enum.each(&parse_line/1)
  end

  defp parse_line(line) do
    line = String.trim(line)
    
    # Skip empty lines and comments
    if line != "" and not String.starts_with?(line, "#") do
      case String.split(line, "=", parts: 2) do
        [key, value] ->
          key = String.trim(key)
          value = clean_value(value)
          System.put_env(key, value)
        
        _ ->
          :skip
      end
    end
  end

  defp clean_value(value) do
    value
    |> String.trim()
    |> String.trim_leading("\"")
    |> String.trim_trailing("\"")
    |> String.trim_leading("'")
    |> String.trim_trailing("'")
  end
end

# ============================================================================
# Example Usage
# ============================================================================

# Load environment
DotEnv.load()

# Access variables
api_key = System.get_env("API_KEY")
endpoint = System.get_env("API_ENDPOINT") || "https://default.api.com"

IO.puts("\n=== Environment Check ===")
IO.puts("API_KEY: #{if api_key, do: "Set (#{String.length(api_key)} chars)", else: "Not set"}")
IO.puts("API_ENDPOINT: #{endpoint}")

# Validate required variables
required_vars = ["API_KEY", "SECRET"]

missing = Enum.filter(required_vars, fn var ->
  is_nil(System.get_env(var))
end)

if missing != [] do
  IO.puts("\n❌ Missing required environment variables: #{Enum.join(missing, ", ")}")
  IO.puts("   Please set them in .env file")
  System.halt(1)
end

IO.puts("\n✅ All required environment variables are set")
