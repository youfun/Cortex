defmodule Cortex.Channels.Supervisor do
  @moduledoc """
  Channel adapter supervisor.

  Starts child specs declared by enabled channel adapters.
  """
  use Supervisor
  require Logger

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    adapters = Application.get_env(:cortex, :channel_adapters, [])

    children =
      adapters
      |> Enum.uniq()
      |> Enum.flat_map(&adapter_child_specs/1)

    Logger.info(
      "[Channels.Supervisor] Channel children: count=#{length(children)} adapters=#{inspect(Enum.uniq(adapters))}"
    )

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp adapter_child_specs(adapter) do
    cond do
      not Code.ensure_loaded?(adapter) ->
        Logger.warning("[Channels.Supervisor] Adapter not loaded: #{inspect(adapter)}")
        []

      function_exported?(adapter, :enabled?, 0) ->
        if adapter.enabled?() do
          Logger.info("[Channels.Supervisor] Adapter enabled: #{inspect(adapter)}")
          adapter.child_specs()
        else
          Logger.warning("[Channels.Supervisor] Adapter disabled: #{inspect(adapter)}")
          []
        end

      true ->
        []
    end
  rescue
    e ->
      Logger.error(
        "[Channels.Supervisor] Failed to load adapter #{inspect(adapter)}: #{Exception.message(e)}"
      )

      []
  end
end
