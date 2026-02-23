defmodule Cortex.Shell.Command do
  @moduledoc """
  Minimal shell command behaviour to replace the `jido_shell` dependency.
  """

  @type emit :: (event :: term() -> :ok)
  @type run_result :: {:ok, term()} | {:error, Cortex.Shell.Error.t()}

  @callback name() :: String.t()
  @callback summary() :: String.t()
  @callback schema() :: term()
  @callback run(state :: map(), args :: map(), emit :: emit()) :: run_result()
end
