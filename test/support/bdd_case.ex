defmodule Cortex.BDDCase do
  @moduledoc """
  Test case for BDD-generated tests.

  This module combines DataCase and ProcessCase to provide both
  database access and supervised processes for BDD integration tests.

  ## Usage

      use Cortex.BDDCase

  This will:
  - Set up Ecto Sandbox for database isolation
  - Start SignalHub, Tools.Registry, and other required processes
  - Properly handle cleanup after each test
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use Cortex.DataCase
      use Cortex.MemoryCase

      import Cortex.BDDCase
    end
  end

  setup context do
    # Get owner_pid from DataCase setup
    owner_pid = Map.get(context, :owner_pid)

    Cortex.ProcessCase.ensure_test_processes()

    if owner_pid do
      # Allow Messages.Writer to access the database
      # This process is started lazily when signals are emitted
      allow_messages_writer(owner_pid)

      # Also allow Tape.Store which may access DB indirectly
      allow_tape_store(owner_pid)
    end

    :ok
  end

  # Allow Messages.Writer process to access the database
  # This is called periodically because the process might not exist yet
  defp allow_messages_writer(owner_pid) do
    spawn_link(fn ->
      # Check multiple times over 1000ms to catch the process when it starts
      Enum.each(0..10, fn i ->
        Process.sleep(i * 100)

        case Process.whereis(Cortex.Messages.Writer) do
          nil ->
            :ok

          pid ->
            try do
              Ecto.Adapters.SQL.Sandbox.allow(Cortex.Repo, owner_pid, pid)
            rescue
              ArgumentError -> :ok
              DBConnection.OwnershipError -> :ok
            end
        end
      end)
    end)
  end

  # Allow Tape.Store process to access the database
  defp allow_tape_store(owner_pid) do
    case Process.whereis(Cortex.History.Tape.Store) do
      nil ->
        :ok

      pid ->
        try do
          Ecto.Adapters.SQL.Sandbox.allow(Cortex.Repo, owner_pid, pid)
        rescue
          ArgumentError -> :ok
          DBConnection.OwnershipError -> :ok
        end
    end
  end
end
