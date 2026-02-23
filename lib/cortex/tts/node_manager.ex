defmodule Cortex.TTS.NodeManager do
  @moduledoc """
  Manages remote GPU nodes for TTS tasks.
  Tracks node availability, capabilities, and heartbeats.
  """
  use GenServer
  require Logger
  alias Cortex.SignalHub

  # 65 seconds
  @heartbeat_timeout 65_000
  # 30 seconds
  @check_interval 30_000

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Lists all registered nodes and their current status.
  """
  def list_nodes do
    GenServer.call(__MODULE__, :list_nodes)
  end

  @doc """
  Registers or updates a node.
  """
  def register_node(node_id, info) do
    GenServer.call(__MODULE__, {:register_node, node_id, info})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Subscribe to node-related signals
    SignalHub.subscribe("tts.node.**")

    # Start periodic health check
    Process.send_after(self(), :check_health, @check_interval)

    # State: %{nodes: %{node_id => %{info: map, status: atom, last_seen: DateTime}}}
    {:ok, %{nodes: %{}}}
  end

  @impl true
  def handle_call(:list_nodes, _from, state) do
    {:reply, state.nodes, state}
  end

  @impl true
  def handle_call({:register_node, node_id, info}, _from, state) do
    now = DateTime.utc_now()

    new_node = %{
      info: info,
      status: :online,
      last_seen: now
    }

    Logger.info("[TTS.NodeManager] Node registered/updated: #{node_id}")
    new_nodes = Map.put(state.nodes, node_id, new_node)
    {:reply, :ok, %{state | nodes: new_nodes}}
  end

  @impl true
  def handle_info({:signal, %Jido.Signal{type: "tts.node.register", data: data}}, state) do
    payload = data.payload || %{}
    node_id = payload.node_id || payload["node_id"]

    if node_id do
      {:reply, :ok, new_state} = handle_call({:register_node, node_id, payload}, nil, state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:signal, %Jido.Signal{type: "tts.node.heartbeat", data: data}}, state) do
    payload = data.payload || %{}
    node_id = payload.node_id || payload["node_id"]

    case Map.get(state.nodes, node_id) do
      nil ->
        # Auto-register on heartbeat if unknown? For now, just ignore or log
        Logger.debug("[TTS.NodeManager] Heartbeat from unknown node: #{node_id}")
        {:noreply, state}

      node ->
        new_node = %{node | last_seen: DateTime.utc_now(), status: :online}
        {:noreply, %{state | nodes: Map.put(state.nodes, node_id, new_node)}}
    end
  end

  @impl true
  def handle_info(:check_health, state) do
    now = DateTime.utc_now()

    new_nodes =
      Map.new(state.nodes, fn {id, node} ->
        diff = DateTime.diff(now, node.last_seen, :millisecond)
        status = if diff > @heartbeat_timeout, do: :offline, else: node.status
        {id, %{node | status: status}}
      end)

    Process.send_after(self(), :check_health, @check_interval)
    {:noreply, %{state | nodes: new_nodes}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[TTS.NodeManager] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end
end
