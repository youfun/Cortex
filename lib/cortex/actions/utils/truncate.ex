defmodule Cortex.Actions.Utils.Truncate do
  @moduledoc """
  Action to truncate text content using various strategies.
  Wraps Cortex.Tools.Truncate.
  """
  require Logger
  alias Cortex.Tools.Truncate

  @required_params [:text]
  @allowed_params [:text, :strategy, :max_lines, :max_bytes, :max_chars]
  @valid_strategies ["head", "tail", "line"]

  def run(params, _context) do
    params = normalize_params(params)

    with :ok <- validate_required(params),
         :ok <- validate_strategy(params) do
      do_truncate(params)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_params(params) do
    Map.new(params, fn
      {k, v} when is_binary(k) ->
        case Cortex.Utils.SafeAtom.to_allowed(k, @allowed_params) do
          {:ok, atom} -> {atom, v}
          {:error, :not_allowed} -> {k, v}
        end

      {k, v} when is_atom(k) ->
        {k, v}
    end)
  end

  defp validate_required(params) do
    missing =
      Enum.filter(@required_params, fn key ->
        case Map.get(params, key) do
          nil -> true
          value when is_binary(value) -> false
          # Non-binary text is considered invalid here
          _ -> true
        end
      end)

    if missing == [] do
      :ok
    else
      {:error, "Missing required parameter: #{Enum.join(missing, ", ")} (must be binary)"}
    end
  end

  defp validate_strategy(params) do
    strategy = Map.get(params, :strategy, "tail")

    if to_string(strategy) in @valid_strategies do
      :ok
    else
      {:error, "Invalid strategy: #{strategy}. valid: #{inspect(@valid_strategies)}"}
    end
  end

  defp do_truncate(params) do
    text = params.text
    strategy_str = to_string(Map.get(params, :strategy, "tail"))

    case strategy_str do
      "line" ->
        max_chars = Map.get(params, :max_chars, 1000)
        result = Truncate.truncate_line(text, max_chars)
        {:ok, Map.from_struct(result)}

      other ->
        strategy = String.to_existing_atom(other)
        opts = []
        opts = if ml = params[:max_lines], do: Keyword.put(opts, :max_lines, ml), else: opts
        opts = if mb = params[:max_bytes], do: Keyword.put(opts, :max_bytes, mb), else: opts

        result = Truncate.truncate(text, strategy, opts)
        {:ok, Map.from_struct(result)}
    end
  end
end
