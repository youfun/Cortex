defmodule Cortex.History.SignalRecorder do
  @moduledoc """
  信号历史记录器。

  订阅信号总线上的所有信号，将其持久化到 ` history.jsonl` 文件中。
  每行一个信号（JSONL 格式），作为系统的"黑匣子"。
  """

  use GenServer
  require Logger

  alias Cortex.SignalHub
  alias Cortex.Workspaces

  @history_file_name "history.jsonl"
  # 每 5 秒刷新一次
  @flush_interval 5_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    workspace_root = Workspaces.workspace_root()
    history_file = Path.join(workspace_root, @history_file_name)

    # 确保目录存在
    File.mkdir_p!(Path.dirname(history_file))

    Logger.info(
      "[SignalRecorder] Starting recorder. pid=#{inspect(self())} history_file=#{history_file}"
    )

    # 订阅所有信号
    SignalHub.subscribe("**")

    # 启动刷新定时器
    Process.send_after(self(), :flush, @flush_interval)

    # 以追加模式打开文件
    case File.open(history_file, [:append, :utf8]) do
      {:ok, file} ->
        {:ok,
         %{
           buffer: [],
           file: file,
           history_file: history_file,
           nonstandard_counts: %{}
         }}

      {:error, reason} ->
        Logger.error("[SignalRecorder] Failed to open history file: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def handle_info({:signal, %Jido.Signal{} = signal}, state) do
    do_record(signal, state)
  end

  def handle_info({:signal, signal}, state) do
    state = note_nonstandard(:signal_tuple_nonstruct, signal, state)
    do_record(signal, state)
  end

  @impl true
  def handle_info(%Jido.Signal{} = signal, state) do
    state = note_nonstandard(:bare_struct, signal, state)
    do_record(signal, state)
  end

  def handle_info(:flush, state) do
    # 仅在有数据时记录 info，无数据时保持静默（debug 级别）
    if Enum.empty?(state.buffer) do
      Logger.debug("[SignalRecorder] Flush triggered, buffer empty.")
    else
      Logger.info("[SignalRecorder] Flushing buffer, size: #{length(state.buffer)}")

      content =
        state.buffer
        |> Enum.reverse()
        |> Enum.join("\n")

      case IO.write(state.file, content <> "\n") do
        :ok -> :file.datasync(state.file)
        {:error, reason} -> Logger.error("[SignalRecorder] Write failed: #{inspect(reason)}")
      end
    end

    Process.send_after(self(), :flush, @flush_interval)
    {:noreply, %{state | buffer: []}}
  end

  def handle_info(_other, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if Map.has_key?(state, :file) && state.file do
      unless Enum.empty?(state.buffer) do
        content = state.buffer |> Enum.reverse() |> Enum.join("\n")
        IO.write(state.file, content <> "\n")
      end

      File.close(state.file)
    end

    :ok
  end

  defp do_record(signal, state) do
    if should_record?(signal) do
      json_line = signal_to_json(signal)
      {:noreply, %{state | buffer: [json_line | state.buffer]}}
    else
      {:noreply, state}
    end
  end

  defp note_nonstandard(kind, signal, state) do
    counts = Map.update(state.nonstandard_counts, kind, 1, &(&1 + 1))
    count = Map.get(counts, kind, 1)

    # Log on first occurrence and then every 100 occurrences to reduce noise.
    if count == 1 or rem(count, 100) == 0 do
      Logger.error(
        "[SignalRecorder] ⚠️ Non-standard signal delivery detected! " <>
          "kind=#{kind} count=#{count} " <>
          "type=#{inspect(get_field(signal, :type))} source=#{inspect(get_field(signal, :source))} " <>
          "— This delivery format will be removed in a future release."
      )
    end

    %{state | nonstandard_counts: counts}
  end

  defp signal_to_json(signal) do
    %{
      id: get_field(signal, :id),
      type: get_field(signal, :type),
      source: get_field(signal, :source),
      time: get_field(signal, :time),
      specversion: get_field(signal, :specversion),
      data: sanitize(get_field(signal, :data)),
      extensions: sanitize(get_field(signal, :extensions) || %{})
    }
    |> Jason.encode!()
  end

  defp get_field(data, field) when is_struct(data), do: Map.get(data, field)
  defp get_field(data, field) when is_map(data), do: Map.get(data, field)
  defp get_field(_, _), do: nil

  defp should_record?(signal) do
    type = get_field(signal, :type)

    if is_binary(type) do
      # Skip very noisy streaming chunk signals in audit log.
      # Also skip low-level memory/kg/ui operations to reduce noise.
      not String.starts_with?(type, "agent.response.chunk") and
        not String.starts_with?(type, "memory.") and
        not String.starts_with?(type, "kg.") and
        not String.starts_with?(type, "ui.")
    else
      true
    end
  end

  defp sanitize(term) when is_binary(term) do
    if String.valid?(term) do
      term
    else
      %{
        "__type__" => "binary",
        "__encoding__" => "base64",
        "data" => Base.encode64(term)
      }
    end
  end

  defp sanitize(term) when is_struct(term) do
    term
    |> Map.from_struct()
    |> sanitize()
  end

  defp sanitize(term) when is_map(term) do
    term
    |> Enum.map(fn {k, v} -> {sanitize_key(k), sanitize(v)} end)
    |> Enum.into(%{})
  end

  defp sanitize(term) when is_list(term), do: Enum.map(term, &sanitize/1)
  defp sanitize(term) when is_tuple(term), do: term |> Tuple.to_list() |> Enum.map(&sanitize/1)
  defp sanitize(term), do: term

  defp sanitize_key(key) when is_atom(key), do: key

  defp sanitize_key(key) when is_binary(key) do
    if String.valid?(key), do: key, else: Base.encode64(key)
  end

  defp sanitize_key(key), do: to_string(key)
end
