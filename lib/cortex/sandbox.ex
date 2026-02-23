defmodule Cortex.Sandbox do
  @moduledoc """
  Sandbox execution abstraction.

  Supports host execution by default. Future implementations can add
  Docker or SSH backends.
  """

  @type exec_result ::
          {:ok, %{stdout: String.t(), stderr: String.t(), exit_code: integer()}}
          | {:error, term()}

  @callback execute(command :: String.t(), opts :: keyword()) :: exec_result
  @callback upload_file(local_path :: String.t(), remote_path :: String.t()) ::
              :ok | {:error, term()}
  @callback download_file(remote_path :: String.t(), local_path :: String.t()) ::
              :ok | {:error, term()}

  @doc """
  Execute a command using the configured sandbox implementation.
  """
  def execute(command, opts \\ []) do
    impl = Keyword.get(opts, :impl, Cortex.Sandbox.Host)
    impl.execute(command, opts)
  end
end
