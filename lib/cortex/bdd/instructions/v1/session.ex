defmodule Cortex.BDD.Instructions.V1.Session do
  @moduledoc false

  alias Cortex.BDD.Instructions.V1.Helpers
  alias Cortex.SignalCatalog
  alias Cortex.SignalHub
  alias Cortex.Session.BranchManager

  @spec capabilities() :: MapSet.t(atom())
  def capabilities do
    MapSet.new([
      :stop_session,
      :switch_session,
      :complete_session_branch,
      :merge_session_branch
    ])
  end

  def run(ctx, kind, name, args) do
    case {kind, name} do
      {:when, :stop_session} ->
        session_id = args.session_id

        case Registry.lookup(Cortex.SessionRegistry, session_id) do
          [{pid, _}] ->
            GenServer.stop(pid)

            SignalHub.emit(
              SignalCatalog.session_shutdown(),
              %{
                provider: "session",
                event: "session",
                action: "shutdown",
                actor: "coordinator",
                origin: %{
                  channel: "system",
                  client: "bdd_test",
                  platform: "test",
                  session_id: session_id
                },
                session_id: session_id
              }
            )

          [] ->
            :ok
        end

        {:ok, ctx}

      {:when, :switch_session} ->
        opts_data = if args.opts, do: Helpers.parse_messages(args.opts), else: %{}
        opts = if is_map(opts_data), do: Map.to_list(opts_data), else: opts_data

        old_session_id = args.old_session_id
        new_session_id = args.new_session_id

        case Registry.lookup(Cortex.SessionRegistry, old_session_id) do
          [{pid, _}] ->
            GenServer.stop(pid)

            SignalHub.emit(
              SignalCatalog.session_shutdown(),
              %{
                provider: "session",
                event: "session",
                action: "shutdown",
                actor: "coordinator",
                origin: %{
                  channel: "system",
                  client: "bdd_test",
                  platform: "test",
                  session_id: old_session_id
                },
                session_id: old_session_id
              }
            )

          [] ->
            :ok
        end

        case Cortex.Agents.LLMAgent.start_link([{:session_id, new_session_id} | opts]) do
          {:ok, pid} ->
            Ecto.Adapters.SQL.Sandbox.allow(Cortex.Repo, self(), pid)

          {:error, {:already_started, pid}} ->
            Ecto.Adapters.SQL.Sandbox.allow(Cortex.Repo, self(), pid)

          {:error, reason} ->
            raise "Failed to start new session: #{inspect(reason)}"
        end

        {:ok, ctx}

      {:when, :complete_session_branch} ->
        result = if args.result, do: Helpers.parse_messages(args.result), else: %{}
        BranchManager.complete_branch(args.branch_session_id, result)
        {:ok, ctx}

      {:when, :merge_session_branch} ->
        strategy = Helpers.parse_strategy_atom(Map.get(args, :strategy, "append"))
        BranchManager.merge_branch(args.branch_session_id, args.target_session_id, strategy)
        {:ok, ctx}

      _ ->
        :no_match
    end
  end
end
