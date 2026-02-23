defmodule Cortex.BDD.Instructions.V1.Signal do
  @moduledoc false

  import ExUnit.Assertions

  alias Cortex.BDD.Instructions.V1.Helpers
  alias Cortex.History.Tape.Store, as: TapeStore
  alias Cortex.SignalHub

  @spec capabilities() :: MapSet.t(atom())
  def capabilities do
    MapSet.new([
      :signal_bus_is_clean,
      :signal_is_emitted,
      :emit_signal,
      :history_file_should_not_contain,
      :history_file_should_contain,
      :assert_signal_emitted,
      :tape_should_contain_entry,
      :tape_should_not_contain_entry,
      :create_tape_branch,
      :create_session_branch,
      :tape_entry_count_should_be,
      :tape_branch_point_should_be,
      :assert_signal_data,
      :wait_for_turn_complete
    ])
  end

  def run(ctx, kind, name, args) do
    case {kind, name} do
      {:given, :signal_bus_is_clean} ->
        if Application.get_env(:cortex, :env) == :test do
          with :ok <- Ecto.Adapters.SQL.Sandbox.checkout(Cortex.Repo) do
            Ecto.Adapters.SQL.Sandbox.mode(Cortex.Repo, {:shared, self()})

            case Process.whereis(Cortex.Messages.Writer) do
              nil -> :ok
              writer_pid -> Ecto.Adapters.SQL.Sandbox.allow(Cortex.Repo, self(), writer_pid)
            end
          end
        end

        _ = Cortex.History.SignalRecorder.start_link()
        history_file = Path.join(Cortex.Workspaces.workspace_root(), "history.jsonl")
        File.write(history_file, "")
        _ = TapeStore.reset()
        {:ok, ctx}

      {:when, :signal_is_emitted} ->
        type = args.type
        data = Helpers.parse_messages(args.data)

        session_id = Map.get(args, :session_id) || Map.get(ctx, :session_id, "bdd_session")

        full_signal =
          Map.merge(
            %{
              provider: "bdd",
              event: "test",
              action: "emit",
              actor: "tester",
              origin: %{
                channel: "bdd",
                client: "test_runner",
                platform: "server",
                session_id: session_id
              }
            },
            data
          )

        SignalHub.emit(type, full_signal)
        Process.sleep(100)
        {:ok, ctx}

      {:when, :emit_signal} ->
        type = args.type
        data = Helpers.parse_messages(args.data)

        session_id = Map.get(args, :session_id) || Map.get(ctx, :session_id, "bdd_session")

        full_signal =
          Map.merge(
            %{
              provider: "bdd",
              event: "test",
              action: "emit",
              actor: "tester",
              origin: %{
                channel: "bdd",
                client: "test_runner",
                platform: "server",
                session_id: session_id
              }
            },
            data
          )

        SignalHub.emit(type, full_signal)
        Process.sleep(100)
        {:ok, ctx}

      {:when, :create_tape_branch} ->
        TapeStore.create_branch(args.source, args.target)
        {:ok, ctx}

      {:when, :create_session_branch} ->
        parent_id = args.parent_session_id
        purpose = Map.get(args, :purpose, "exploration")
        branch_id = Map.get(args, :branch_id) || Map.get(ctx, :branch_id)

        opts =
          if branch_id, do: [branch_id: branch_id, purpose: purpose], else: [purpose: purpose]

        {:ok, actual_branch_id} = Cortex.Session.BranchManager.create_branch(parent_id, opts)

        Process.sleep(200)
        {:ok, Map.put(ctx, :last_branch_id, actual_branch_id)}

      {:then, :tape_entry_count_should_be} ->
        Process.sleep(100)
        session_id = args.session_id
        limit = Map.get(args, :limit)

        entries =
          if limit do
            TapeStore.list_entries(session_id, limit: limit)
          else
            TapeStore.list_entries(session_id)
          end

        actual_count = length(entries)

        assert actual_count == args.expected,
               "Expected #{args.expected} entries in Tape for session #{session_id}" <>
                 if(limit, do: " with limit #{limit}", else: "") <> ", but got #{actual_count}"

        {:ok, ctx}

      {:then, :tape_branch_point_should_be} ->
        Process.sleep(200)
        branch_session_id = args.branch_session_id
        entries = TapeStore.list_entries(nil)

        found =
          Enum.find(entries, fn e ->
            type = Map.get(e.payload, :type) || Map.get(e.payload, "type")
            data = Map.get(e.payload, :data) || Map.get(e.payload, "data")

            type == "session.branch.created" and
              (Helpers.payload_get(data, :branch_session_id) == branch_session_id or
                 Helpers.payload_get(data, "branch_session_id") == branch_session_id)
          end)

        if found do
          data = Map.get(found.payload, :data) || Map.get(found.payload, "data")

          actual_point =
            Helpers.payload_get(data, :branch_point) || Helpers.payload_get(data, "branch_point")

          assert actual_point == args.expected,
                 "Expected branch_point #{args.expected}, but got #{inspect(actual_point)}"
        else
          flunk(
            "Could not find session.branch.created signal for #{branch_session_id} in Tape. Entries checked: #{length(entries)}"
          )
        end

        {:ok, ctx}

      {:then, :history_file_should_not_contain} ->
        history_file = Path.join(Cortex.Workspaces.workspace_root(), "history.jsonl")
        Helpers.flush_signal_recorder()

        content = File.read!(history_file)

        refute content =~ "\"type\":\"#{args.type}\"",
               "History file should NOT contain signal type: #{args.type}"

        {:ok, ctx}

      {:then, :history_file_should_contain} ->
        history_file = Path.join(Cortex.Workspaces.workspace_root(), "history.jsonl")
        Helpers.flush_signal_recorder()

        content = File.read!(history_file)

        assert content =~ "\"type\":\"#{args.type}\"",
               "History file SHOULD contain signal type: #{args.type}"

        {:ok, ctx}

      {:then, :assert_signal_emitted} ->
        history_file = Path.join(Cortex.Workspaces.workspace_root(), "history.jsonl")
        Helpers.flush_signal_recorder()

        content = File.read!(history_file)
        lines = String.split(content, "\n", trim: true)

        session_id = Map.get(args, :session_id)

        found =
          Enum.any?(lines, fn line ->
            case Jason.decode(line) do
              {:ok, signal} ->
                type = Map.get(signal, "type")
                data = Map.get(signal, "data", %{})
                payload = Map.get(data, "payload", %{})
                origin = Map.get(data, "origin", %{})

                signal_session_id =
                  Map.get(payload, "session_id") ||
                    Map.get(origin, "session_id") ||
                    Map.get(payload, :session_id) ||
                    Map.get(origin, :session_id)

                type == args.type and (is_nil(session_id) or signal_session_id == session_id)

              _ ->
                false
            end
          end)

        assert found,
               "Expected signal #{args.type} to be emitted" <>
                 if(session_id, do: " for session #{session_id}", else: "")

        {:ok, ctx}

      {:then, :tape_should_contain_entry} ->
        Process.sleep(100)
        session_id = Map.get(args, :session_id)
        entries = TapeStore.list_entries(session_id)
        expected_type = args.type
        expected_content = Map.get(args, :content)

        found =
          Enum.any?(entries, fn entry ->
            entry_type =
              get_in(entry, [:payload, :type]) ||
                get_in(entry, [:payload, "type"])

            entry_data =
              get_in(entry, [:payload, :data]) ||
                get_in(entry, [:payload, "data"])

            match_type = to_string(entry_type) == expected_type

            match_content =
              if expected_content do
                inspect(entry_data) =~ expected_content
              else
                true
              end

            match_type and match_content
          end)

        msg =
          "Tape SHOULD contain entry of type: #{expected_type}" <>
            if(expected_content, do: " with content: #{expected_content}", else: "") <>
            if session_id, do: " in session: #{session_id}", else: ""

        assert found,
               msg <>
                 ". Entries: " <>
                 inspect(
                   Enum.map(
                     entries,
                     &{get_in(&1, [:payload, :type]), get_in(&1, [:payload, :data])}
                   )
                 )

        {:ok, ctx}

      {:then, :tape_should_not_contain_entry} ->
        Process.sleep(100)
        session_id = Map.get(args, :session_id)
        entries = TapeStore.list_entries(session_id)
        expected_type = args.type
        expected_content = Map.get(args, :content)

        found =
          Enum.any?(entries, fn entry ->
            entry_type =
              get_in(entry, [:payload, :type]) ||
                get_in(entry, [:payload, "type"])

            entry_data =
              get_in(entry, [:payload, :data]) ||
                get_in(entry, [:payload, "data"])

            match_type = to_string(entry_type) == expected_type

            match_content =
              if expected_content do
                inspect(entry_data) =~ expected_content
              else
                true
              end

            match_type and match_content
          end)

        msg =
          "Tape should NOT contain entry of type: #{expected_type}" <>
            if(expected_content, do: " with content: #{expected_content}", else: "") <>
            if session_id, do: " in session: #{session_id}", else: ""

        refute found, msg
        {:ok, ctx}

      {:then, :assert_signal_data} ->
        history_file = Path.join(Cortex.Workspaces.workspace_root(), "history.jsonl")
        Process.send(Cortex.History.SignalRecorder, :flush, [])
        Process.sleep(100)

        content = File.read!(history_file)
        lines = String.split(content, "\n", trim: true)

        found =
          Enum.find(Enum.reverse(lines), fn line ->
            case Jason.decode(line) do
              {:ok, signal} ->
                Map.get(signal, "type") == args.type

              _ ->
                false
            end
          end)

        assert found, "No signal of type #{args.type} found in history"

        {:ok, signal} = Jason.decode(found)

        full_path = ["data" | String.split(args.path, ".")]
        actual_value = get_in(signal, full_path)
        expected_value = args.expected

        actual_str = to_string(actual_value)

        assert actual_str == expected_value,
               "Expected #{args.path} to be #{expected_value}, but got #{actual_str} in signal #{args.type}"

        {:ok, ctx}

      {:then, :wait_for_turn_complete} ->
        session_id = args.session_id
        max_wait_ms = 10_000
        check_interval_ms = 100
        max_attempts = div(max_wait_ms, check_interval_ms)

        Helpers.wait_for_turn_end(session_id, max_attempts, check_interval_ms)
        {:ok, ctx}

      _ ->
        :no_match
    end
  end
end
