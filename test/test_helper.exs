ExUnit.start()

# Use the project root as the workspace root in tests so file assertions align
Application.put_env(:cortex, :workspace_root, File.cwd!())

# Reset the sqlite test database file so each `mix test` run starts clean.
# Many tests assume an empty DB; without this, data can persist across runs and
# cause unique constraint failures.
db_path = Path.expand("../cortex_test.db", __DIR__)

Enum.each([db_path, db_path <> "-wal", db_path <> "-shm"], fn path ->
  case File.rm(path) do
    :ok -> :ok
    {:error, :enoent} -> :ok
    {:error, _} -> :ok
  end
end)

# Run migrations using a non-sandbox pool to avoid rollback semantics.
case Process.whereis(Cortex.Repo) do
  nil -> :ok
  pid -> GenServer.stop(pid)
end

case Cortex.Repo.start_link(pool: DBConnection.ConnectionPool) do
  {:ok, _} -> :ok
  {:error, {:already_started, _}} -> :ok
end

# Run migrations directly (not via with_repo which stops the repo afterward)
migrations_path = Path.join([:code.priv_dir(:cortex) |> to_string(), "repo", "migrations"])
Ecto.Migrator.run(Cortex.Repo, migrations_path, :up, all: true)

# Fail fast if migrations did not create the schema_migrations table
case Ecto.Adapters.SQL.query(
       Cortex.Repo,
       "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_migrations'",
       []
     ) do
  {:ok, %{rows: [[_]]}} -> :ok
  other -> raise "Test DB migrations did not run (schema_migrations missing): #{inspect(other)}"
end

case Process.whereis(Cortex.Repo) do
  nil -> :ok
  pid -> GenServer.stop(pid)
end

# Now start the full application (which may query the database)
# The Repo is already started, so the application will use the existing one
{:ok, _} = Application.ensure_all_started(:cortex)

# Ensure Repo is started before sandbox configuration
case Process.whereis(Cortex.Repo) do
  nil ->
    case Cortex.Repo.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      {:error, _} -> :ok
    end

  _pid ->
    :ok
end

# Switch back to :manual mode for test isolation
# Wait briefly for Repo to be fully registered in ETS after application start
Process.sleep(100)
Ecto.Adapters.SQL.Sandbox.mode(Cortex.Repo, :manual)

# Provide a shared sandbox owner for tests that don't use DataCase/ConnCase.
# This prevents background processes (e.g. Messages.Writer) from crashing
# when they touch the DB during unit-style tests.
shared_owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Cortex.Repo, shared: true)
Ecto.Adapters.SQL.Sandbox.mode(Cortex.Repo, {:shared, shared_owner})

shared_allowlist = [
  Cortex.Messages.Writer,
  Cortex.History.SignalRecorder,
  Cortex.History.Tape.Store,
  Cortex.Config.Metadata,
  Cortex.Memory.Store
]

spawn_link(fn ->
  Enum.each(0..10, fn i ->
    Process.sleep(i * 50)

    Enum.each(shared_allowlist, fn name ->
      if Process.whereis(Cortex.Repo) do
        case Process.whereis(name) do
          nil ->
            :ok

          pid ->
            try do
              Ecto.Adapters.SQL.Sandbox.allow(Cortex.Repo, shared_owner, pid)
            rescue
              ArgumentError -> :ok
              DBConnection.OwnershipError -> :ok
            end
        end
      end
    end)
  end)
end)

# Ensure Jido AgentSupervisor is running for tests that spawn agents
agent_supervisor = Jido.agent_supervisor_name(Cortex.Jido)

case Process.whereis(agent_supervisor) do
  nil ->
    case Process.whereis(Cortex.Jido) do
      nil ->
        case Jido.start_link(name: Cortex.Jido) do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
          {:error, _} -> :ok
        end

      _pid ->
        :ok
    end

  _pid ->
    :ok
end

# Setup Mimic for RouteChat dependencies
Mimic.copy(ReqLLM.Generation)
Mimic.copy(Cortex.LLM.Config)
Mimic.copy(Cortex.Actions.AI.RouteChat)
Mimic.copy(ReqLLM)
Mimic.copy(ReqLLM.Response)
Mimic.copy(ReqLLM.ToolCall)
Mimic.copy(Cortex.LLM.Client)
Mimic.copy(Cortex.Config.Metadata)
Mimic.copy(Cortex.Tools.ToolRunner)
