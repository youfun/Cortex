defmodule Cortex.BDD.Instructions.V1.Agent do
  @moduledoc false

  import ExUnit.Assertions

  alias Cortex.Agents.Retry
  alias Cortex.BDD.Instructions.V1.Helpers
  alias Cortex.History.Tape.Store, as: TapeStore
  alias Cortex.SignalCatalog
  alias Cortex.SignalHub

  @spec capabilities() :: MapSet.t(atom())
  def capabilities do
    MapSet.new([
      :start_agent,
      :restart_agent,
      :assert_agent_history_count,
      :steering_inject,
      :assert_steering_queue_size,
      :classify_error,
      :retry_delay,
      :retry_should_retry,
      :assert_error_class,
      :assert_delay_ms,
      :assert_should_retry,
      :send_chat_message
    ])
  end

  def run(ctx, kind, name, args) do
    case {kind, name} do
      {:given, :start_agent} ->
        session_id = Map.get(args, :session_id) || Map.get(ctx, :session_id, "bdd_session")
        _ = Registry.start_link(keys: :unique, name: Cortex.SessionRegistry)
        _ = Task.Supervisor.start_link(name: Cortex.AgentTaskSupervisor)

        try do
          Ecto.Adapters.SQL.Sandbox.checkout(Cortex.Repo)
        rescue
          _ -> :ok
        end

        Helpers.allow_supervised_db_processes()

        _result =
          case Cortex.Agents.LLMAgent.start_link(session_id: session_id) do
            {:ok, pid} ->
              Ecto.Adapters.SQL.Sandbox.allow(Cortex.Repo, self(), pid)
              {:ok, pid}

            {:error, {:already_started, pid}} ->
              Ecto.Adapters.SQL.Sandbox.allow(Cortex.Repo, self(), pid)
              {:ok, pid}

            {:error, reason} ->
              raise "Failed to start LLMAgent: #{inspect(reason)}"
          end

        SignalHub.emit(
          SignalCatalog.agent_turn_start(),
          %{
            provider: "agent",
            event: "turn",
            action: "start",
            actor: "bdd_test",
            origin: %{
              channel: "test",
              client: "bdd",
              platform: "test",
              session_id: session_id
            },
            session_id: session_id,
            turn: 1
          },
          source: "/test/bdd"
        )

        Process.sleep(50)
        {:ok, ctx}

      {:when, :restart_agent} ->
        session_id = args.session_id

        case Registry.lookup(Cortex.SessionRegistry, session_id) do
          [{pid, _}] ->
            GenServer.stop(pid)
            Process.sleep(100)

          [] ->
            :ok
        end

        try do
          Ecto.Adapters.SQL.Sandbox.checkout(Cortex.Repo)
        rescue
          _ -> :ok
        end

        case Cortex.Agents.LLMAgent.start_link(session_id: session_id) do
          {:ok, pid} ->
            Ecto.Adapters.SQL.Sandbox.allow(Cortex.Repo, self(), pid)
            {:ok, ctx}

          {:error, {:already_started, pid}} ->
            Ecto.Adapters.SQL.Sandbox.allow(Cortex.Repo, self(), pid)
            {:ok, ctx}

          {:error, reason} ->
            raise "Failed to restart LLMAgent: #{inspect(reason)}"
        end

      {:then, :assert_agent_history_count} ->
        session_id = args.session_id
        min_count = args.min_count

        case Registry.lookup(Cortex.SessionRegistry, session_id) do
          [{_pid, _}] ->
            history = TapeStore.list_entries(session_id)
            count = length(history)

            assert count >= min_count,
                   "Agent history count #{count} is less than expected #{min_count}"

          [] ->
            raise "LLMAgent not found for session #{session_id}"
        end

        {:ok, ctx}

      {:when, :steering_inject} ->
        session_id = Map.get(ctx, :session_id, "bdd_session")
        content = args.content

        SignalHub.emit(
          "agent.steering.inject",
          %{
            provider: "ui",
            event: "chat",
            action: "request",
            actor: "user",
            origin: %{channel: "ui", client: "web", platform: "server", session_id: session_id},
            content: content,
            session_id: session_id
          },
          source: "/ui/web/chat"
        )

        {:ok, ctx}

      {:when, :classify_error} ->
        class = Retry.classify_error(args.error)
        {:ok, Map.put(ctx, :retry_error_class, class)}

      {:when, :retry_delay} ->
        delay = Retry.delay_ms(args.attempt)
        {:ok, Map.put(ctx, :retry_delay_ms, delay)}

      {:when, :retry_should_retry} ->
        class = String.to_existing_atom(args.error_class)
        result = Retry.should_retry?(class, args.attempt)
        {:ok, Map.put(ctx, :retry_should_retry, result)}

      {:then, :assert_steering_queue_size} ->
        session_id = Map.get(ctx, :session_id, "bdd_session")
        expected = args.expected

        case Registry.lookup(Cortex.SessionRegistry, session_id) do
          [{pid, _}] ->
            state = :sys.get_state(pid)
            actual = length(state.steering_queue)

            assert actual == expected,
                   "Expected steering queue size #{expected}, but got #{actual}"

          [] ->
            raise "LLMAgent not found for session #{session_id}"
        end

        {:ok, ctx}

      {:then, :assert_error_class} ->
        actual = Map.fetch!(ctx, :retry_error_class)

        assert to_string(actual) == args.expected,
               "期望错误分类=#{args.expected}，实际：#{actual}"

        {:ok, ctx}

      {:then, :assert_delay_ms} ->
        actual = Map.fetch!(ctx, :retry_delay_ms)

        assert actual == args.expected,
               "期望延迟=#{args.expected}ms，实际：#{actual}ms"

        {:ok, ctx}

      {:then, :assert_should_retry} ->
        actual = Map.fetch!(ctx, :retry_should_retry)

        assert actual == args.expected,
               "期望 should_retry=#{args.expected}，实际：#{actual}"

        {:ok, ctx}

      {:when, :send_chat_message} ->
        session_id = args.session_id
        content = args.content

        case Registry.lookup(Cortex.SessionRegistry, session_id) do
          [] ->
            try do
              Ecto.Adapters.SQL.Sandbox.checkout(Cortex.Repo)
            rescue
              _ -> :ok
            end

            case Cortex.Agents.LLMAgent.start_link(session_id: session_id) do
              {:ok, pid} ->
                Ecto.Adapters.SQL.Sandbox.allow(Cortex.Repo, self(), pid)
                :ok

              {:error, {:already_started, pid}} ->
                Ecto.Adapters.SQL.Sandbox.allow(Cortex.Repo, self(), pid)
                :ok

              {:error, reason} ->
                raise "Failed to start LLMAgent: #{inspect(reason)}"
            end

          [{_pid, _}] ->
            :ok
        end

        SignalHub.emit(
          SignalCatalog.agent_chat_request(),
          %{
            provider: "bdd_test",
            event: "chat",
            action: "request",
            actor: "user",
            origin: %{
              channel: "test",
              client: "bdd",
              platform: "test",
              session_id: session_id
            },
            content: content,
            session_id: session_id
          },
          source: "/test/bdd"
        )

        Process.sleep(100)

        {:ok, ctx}

      _ ->
        :no_match
    end
  end
end
