defmodule Cortex.Hooks.SkillInvokeHook do
  @moduledoc """
  Detects /skill or @skill chat commands and rewrites them into
  explicit skill invocation instructions for the LLM agent.
  """

  @behaviour Cortex.Agents.Hook

  alias Cortex.Skills.Loader

  @skill_regex ~r/^\s*(?:\/skill|@skill)\s+(?<name>[A-Za-z0-9_-]+)(?:\s+(?<args>.*))?\s*$/s

  @impl true
  def on_input(state, message) when is_binary(message) do
    case parse_command(message) do
      {:ok, %{name: name, args: args}} ->
        case Loader.load_skill(name) do
          {:ok, _skill} ->
            {:ok, build_message(name, args), state}

          {:error, :not_found} ->
            {:ok, "Skill not found: #{name}.", state}

          {:error, _reason} ->
            {:ok, "Skill load failed: #{name}.", state}
        end

      :no_match ->
        {:ok, message, state}
    end
  end

  def on_input(state, message), do: {:ok, message, state}

  def parse_command(message) when is_binary(message) do
    case Regex.named_captures(@skill_regex, message) do
      %{"name" => name} = captures ->
        args = captures |> Map.get("args", "") |> String.trim()
        {:ok, %{name: name, args: args}}

      _ ->
        :no_match
    end
  end

  def parse_command(_message), do: :no_match

  def build_message(name, args) do
    args = String.trim(to_string(args || ""))

    if args == "" do
      "Use skill #{name}. Ask the user for the missing prompt if needed."
    else
      "Use skill #{name}. User input: #{args}"
    end
  end
end
