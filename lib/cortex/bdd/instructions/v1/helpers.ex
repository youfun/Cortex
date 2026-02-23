defmodule Cortex.BDD.Instructions.V1.Helpers do
  @moduledoc false

  alias Cortex.Utils.SafeAtom

  def parse_messages(messages) when is_list(messages), do: messages

  def parse_messages(messages) when is_binary(messages) do
    messages =
      if String.starts_with?(messages, "'") and String.ends_with?(messages, "'") do
        String.slice(messages, 1..-2//1)
      else
        messages
      end

    Jason.decode!(messages)
  end

  def parse_messages(_), do: []

  def parse_list(value) when is_list(value), do: value

  def parse_list(value) when is_binary(value), do: parse_messages(value)

  def parse_list(_), do: []

  def parse_modules(value) do
    value
    |> parse_list()
    |> Enum.map(fn
      module when is_atom(module) -> module
      module when is_binary(module) -> module_from_string(module)
      other -> raise "Invalid module reference: #{inspect(other)}"
    end)
  end

  def module_from_string(module) when is_atom(module), do: module

  def module_from_string(module) when is_binary(module) do
    module
    |> String.split(".")
    |> Module.concat()
  end

  def get_text(ctx, var_name) do
    Map.get(ctx, safe_existing_atom(var_name)) || Map.get(ctx, var_name) || var_name
  end

  def parse_decision_atom(decision) when is_binary(decision) do
    case String.downcase(decision) do
      "allow" -> :allow
      "allow_always" -> :allow_always
      "deny" -> :deny
      _ -> :deny
    end
  end

  def parse_decision_atom(_), do: :deny

  def parse_duration_atom(duration) when is_binary(duration) do
    case String.downcase(duration) do
      "once" -> :once
      "always" -> :always
      _ -> :once
    end
  end

  def parse_duration_atom(_), do: :once

  def parse_strategy_atom(strategy) when is_binary(strategy) do
    case String.downcase(strategy) do
      "append" -> :append
      "replace" -> :replace
      _ -> :append
    end
  end

  def parse_strategy_atom(_), do: :append

  def safe_existing_atom(value) when is_binary(value) do
    case SafeAtom.to_existing(value) do
      {:ok, atom} -> atom
      {:error, :not_found} -> nil
    end
  end

  def safe_existing_atom(_), do: nil

  def get_message_content(msg) do
    content = Map.get(msg, :content) || Map.get(msg, "content")

    case content do
      text when is_binary(text) ->
        text

      parts when is_list(parts) ->
        parts
        |> Enum.map(fn
          %{text: text} -> text
          %{"text" => text} -> text
          _ -> ""
        end)
        |> Enum.join(" ")

      _ ->
        ""
    end
  end

  def payload_get(data, key) when is_map(data) do
    payload =
      case data do
        %{payload: p} when is_map(p) -> p
        %{"payload" => p} when is_map(p) -> p
        _ -> %{}
      end

    Map.get(payload, key) ||
      Map.get(payload, to_string(key)) ||
      Map.get(data, key) ||
      Map.get(data, to_string(key))
  end

  def payload_get(_, _), do: nil

  def allow_supervised_db_processes do
    processes_to_allow = [
      Cortex.Messages.Writer,
      Cortex.History.SignalRecorder,
      Cortex.Config.Metadata
    ]

    Enum.each(processes_to_allow, fn process_name ->
      case Process.whereis(process_name) do
        nil ->
          :ok

        pid ->
          Ecto.Adapters.SQL.Sandbox.allow(Cortex.Repo, self(), pid)
      end
    end)
  end

  def wait_for_turn_end(session_id, max_attempts, check_interval_ms) do
    history_file = Path.join(Cortex.Workspaces.workspace_root(), "history.jsonl")

    Enum.reduce_while(1..max_attempts, nil, fn attempt, _acc ->
      flush_signal_recorder(check_interval_ms)

      if File.exists?(history_file) do
        content = File.read!(history_file)
        lines = String.split(content, "\n", trim: true)

        found =
          Enum.any?(lines, fn line ->
            case Jason.decode(line) do
              {:ok, signal} ->
                signal_type = Map.get(signal, "type")
                signal_data = Map.get(signal, "data", %{})

                signal_session_id =
                  Map.get(signal_data, "session_id") || Map.get(signal_data, :session_id)

                signal_type == "agent.turn.end" and signal_session_id == session_id

              _ ->
                false
            end
          end)

        if found do
          {:halt, :ok}
        else
          if attempt == max_attempts do
            raise "Timeout waiting for agent.turn.end signal for session #{session_id} after #{max_attempts * check_interval_ms}ms"
          else
            {:cont, nil}
          end
        end
      else
        if attempt == max_attempts do
          raise "History file not found while waiting for agent.turn.end"
        else
          {:cont, nil}
        end
      end
    end)
  end

  def flush_signal_recorder(wait_ms \\ 100) do
    case Process.whereis(Cortex.History.SignalRecorder) do
      nil ->
        :ok

      pid ->
        Process.send(pid, :flush, [])
        Process.sleep(wait_ms)
        :ok
    end
  end
end
