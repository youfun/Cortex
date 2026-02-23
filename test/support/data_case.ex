defmodule Cortex.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Cortex.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Cortex.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Cortex.DataCase
    end
  end

  setup tags do
    pid = Cortex.DataCase.setup_sandbox(tags)

    Cortex.ProcessCase.ensure_test_processes()

    # Reset global settings cache to avoid cross-test leakage
    Enum.each(
      ["skill_default_model", "arena_primary_model", "arena_secondary_model"],
      fn key -> :persistent_term.erase({Cortex.Config.Settings, key}) end
    )

    # Allow any supervised processes to access the database
    unless tags[:skip_db_allow] do
      allow_supervised_processes(pid)
    end

    # Return the owner PID so tests can manually allow additional processes
    {:ok, owner_pid: pid}
  end

  @doc """
  Sets up the sandbox based on the test tags.
  Returns the owner PID for manual process allowance.
  """
  def setup_sandbox(tags) do
    ensure_repo_started()
    Ecto.Adapters.SQL.Sandbox.mode(Cortex.Repo, :manual)
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Cortex.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    pid
  end

  @doc """
  Allows a specific process to access the database in tests.

  Prefer passing the `owner_pid` returned from `setup` to avoid opening
  additional sandbox owners.

  ## Examples

      setup %{owner_pid: owner_pid} do
        {:ok, worker_pid} = start_supervised(MyWorker)
        Cortex.DataCase.allow_process(owner_pid, worker_pid)
        :ok
      end
  """
  def allow_process(owner_pid, pid) when is_pid(owner_pid) and is_pid(pid) do
    Ecto.Adapters.SQL.Sandbox.allow(Cortex.Repo, owner_pid, pid)
  end

  def allow_process(pid) when is_pid(pid) do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Cortex.Repo, shared: true)
    Ecto.Adapters.SQL.Sandbox.allow(Cortex.Repo, owner, pid)
  end

  # Automatically allow common supervised processes that need DB access
  def allow_supervised_processes(owner_pid) do
    processes_to_allow = [
      # 写入 display_messages 表
      Cortex.Messages.Writer,
      # 可能写入 signals 表  
      Cortex.History.SignalRecorder,
      # 读取 llm_models 表
      Cortex.Config.Metadata
    ]

    Enum.each(processes_to_allow, fn process_name ->
      case Process.whereis(process_name) do
        nil ->
          :ok

        pid ->
          try do
            Ecto.Adapters.SQL.Sandbox.allow(Cortex.Repo, owner_pid, pid)
          rescue
            # If the process already has access, ignore the error
            ArgumentError -> :ok
          end
      end
    end)

    # Also set up a periodic check to allow any newly spawned processes
    # This is needed because Messages.Writer might be started after the test begins
    spawn_link(fn ->
      Process.sleep(50)

      Enum.each(processes_to_allow, fn process_name ->
        case Process.whereis(process_name) do
          nil ->
            :ok

          pid ->
            try do
              Ecto.Adapters.SQL.Sandbox.allow(Cortex.Repo, owner_pid, pid)
            rescue
              ArgumentError -> :ok
            end
        end
      end)
    end)
  end

  defp ensure_repo_started do
    case Process.whereis(Cortex.Repo) do
      nil ->
        case Cortex.Repo.start_link() do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
          error -> error
        end

      _ ->
        :ok
    end
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
