#!/usr/bin/env elixir
# Purpose: Test multimodal APIs (images, audio, vision models)
# Usage: elixir scripts/multimodal_debug.exs

Mix.install([
  {:req, "~> 0.5"},
  {:req_llm, "~> 1.0"}
  # Add other dependencies like {:jason, "~> 1.4"} if needed
])

# ============================================================================
# Load Environment Variables
# ============================================================================

defmodule DotEnv do
  def load(path \\ nil) do
    paths = if path, do: [path], else: [".env", "../.env", "../../.env"]
    
    case Enum.find(paths, &File.exists?/1) do
      nil ->
        IO.puts("⚠️  No .env file found")
      found_path ->
        IO.puts("✅ Loading: #{Path.expand(found_path)}")
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
          [key, val] ->
            val = val |> String.trim() |> String.trim("\"") |> String.trim("'")
            System.put_env(String.trim(key), val)
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

# Update these paths for your test files
image_path = "./test_image.png"
api_key = System.get_env("OPENROUTER_API_KEY") || System.get_env("API_KEY")

if is_nil(api_key) do
  IO.puts("❌ ERROR: API key not found")
  IO.puts("   Set OPENROUTER_API_KEY or API_KEY in .env file")
  System.halt(1)
end

# Set for ReqLLM to pick up
System.put_env("OPENROUTER_API_KEY", api_key)

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("  Configuration")
IO.puts(String.duplicate("=", 60) <> "\n")
IO.puts("Image path: #{image_path}")
IO.puts("API key: #{String.slice(api_key, 0, 10)}...#{String.slice(api_key, -4, 4)}")

# ============================================================================
# Load Image (if testing with image)
# ============================================================================

{image_binary, mime_type} = 
  if File.exists?(image_path) do
    IO.puts("\n✅ Image file found")
    binary = File.read!(image_path)
    extension = Path.extname(image_path) |> String.downcase()
    mime = case extension do
      ".png" -> "image/png"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".webp" -> "image/webp"
      _ -> "image/jpeg"
    end
    IO.puts("   Size: #{byte_size(binary)} bytes")
    IO.puts("   MIME: #{mime}")
    {binary, mime}
  else
    IO.puts("\n⚠️  Image file not found: #{image_path}")
    IO.puts("   Skipping image tests...")
    {nil, nil}
  end

# ============================================================================
# Test 1: Text-Only Request
# ============================================================================

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("  Test 1: Text-Only Request")
IO.puts(String.duplicate("=", 60) <> "\n")

text_model = "openrouter:google/gemini-2.0-flash-exp:free"
messages = [%{role: :user, content: "Say hello in 5 words or less."}]

case ReqLLM.generate_text(text_model, messages) do
  {:ok, response} ->
    IO.puts("✅ Success!")
    IO.puts("Response: #{response.message.content}")
    
  {:error, reason} ->
    IO.puts("❌ Failed")
    IO.inspect(reason, label: "Error")
end

# ============================================================================
# Test 2: Image Request (Vision Model)
# ============================================================================

if image_binary do
  IO.puts("\n" <> String.duplicate("=", 60))
  IO.puts("  Test 2: Vision Model - Image Analysis")
  IO.puts(String.duplicate("=", 60) <> "\n")

  vision_model = "openrouter:google/gemini-2.0-flash-exp:free"
  
  # Using ReqLLM's Context API for multimodal
  context = ReqLLM.Context.new([
    ReqLLM.Context.user([
      ReqLLM.Message.ContentPart.text("Describe this image in one sentence."),
      ReqLLM.Message.ContentPart.image(image_binary, mime_type)
    ])
  ])

  case ReqLLM.generate_text(vision_model, context) do
    {:ok, response} ->
      IO.puts("✅ Success!")
      IO.puts("Description: #{ReqLLM.Response.text(response)}")
      IO.puts("\nUsage: #{inspect(response.usage)}")
      
    {:error, reason} ->
      IO.puts("❌ Failed")
      IO.inspect(reason, label: "Error")
  end

  # ============================================================================
  # Test 3: Base64 Image URL Format (Alternative)
  # ============================================================================

  IO.puts("\n" <> String.duplicate("=", 60))
  IO.puts("  Test 3: Base64 Data URL Format")
  IO.puts(String.duplicate("=", 60) <> "\n")

  base64_data = Base.encode64(image_binary)
  data_url = "data:#{mime_type};base64,#{base64_data}"
  
  IO.puts("Data URL length: #{String.length(data_url)} chars")
  IO.puts("Note: Some APIs prefer base64 data URLs over raw binary")
  
  # If using a library that expects data URLs, you can use this format
  # Check the library documentation for the correct format
end

# ============================================================================
# Test 4: Comparing Multiple Approaches
# ============================================================================

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("  Test 4: Approach Comparison")
IO.puts(String.duplicate("=", 60) <> "\n")

approaches = [
  {"Simple message format", fn ->
    ReqLLM.generate_text(text_model, [%{role: :user, content: "Test"}])
  end},
  {"Context API format", fn ->
    ctx = ReqLLM.Context.new([ReqLLM.Context.user("Test")])
    ReqLLM.generate_text(text_model, ctx)
  end}
]

Enum.each(approaches, fn {name, func} ->
  IO.puts("\nTesting: #{name}")
  case func.() do
    {:ok, _} -> IO.puts("  ✅ Works")
    {:error, reason} -> IO.puts("  ❌ Failed: #{inspect(reason)}")
  end
end)

# ============================================================================
# Summary
# ============================================================================

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("  Tests Complete")
IO.puts(String.duplicate("=", 60) <> "\n")

IO.puts("""
Key Findings:
- Text-only requests: Use simple message list or Context API
- Image requests: Use ReqLLM.Message.ContentPart.image(binary, mime_type)
- Some providers support data URLs, others require binary
- Always check provider documentation for supported formats
""")
