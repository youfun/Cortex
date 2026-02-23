defmodule Cortex.Sandbox.Host do
  @moduledoc """
  Host sandbox implementation using Port.
  """

  @behaviour Cortex.Sandbox

  alias Cortex.Workspaces

  @impl true
  def execute(command, opts) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    workdir = Keyword.get(opts, :workdir, Workspaces.ensure_workspace_root!())
    on_chunk = Keyword.get(opts, :on_chunk)

    # On Windows, we often need to run commands through cmd /c
    full_command =
      if :os.type() == {:win32, :nt} do
        "cmd /c #{command}"
      else
        command
      end

    port =
      Port.open({:spawn, full_command}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:cd, workdir}
      ])

    collect_output(port, [], on_chunk, timeout)
  end

  @impl true
  def upload_file(_local_path, _remote_path), do: {:error, :not_supported}

  @impl true
  def download_file(_remote_path, _local_path), do: {:error, :not_supported}

  defp collect_output(port, acc, on_chunk, timeout) do
    receive do
      {^port, {:data, data}} ->
        if is_function(on_chunk, 1), do: on_chunk.(data)
        collect_output(port, [data | acc], on_chunk, timeout)

      {^port, {:exit_status, code}} ->
        output = acc |> Enum.reverse() |> Enum.join()
        {:ok, %{stdout: output, stderr: "", exit_code: code}}
    after
      timeout ->
        Port.close(port)
        {:error, :timeout}
    end
  end
end
