defmodule Cortex.Core.PermissionTracker do
  use GenServer

  require Logger

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Tracks a pending permission request.
  """
  def track_request(request_id, context) do
    GenServer.cast(__MODULE__, {:track_request, request_id, context})
  end

  @doc """
  Gets details of a pending request.
  """
  def get_request(request_id) do
    GenServer.call(__MODULE__, {:get_request, request_id})
  end

  @doc """
  Resolves a request with a decision.
  """
  def resolve_request(request_id, decision) do
    GenServer.cast(__MODULE__, {:resolve_request, request_id, decision})
  end

  @doc """
  Checks if an action is already authorized for a given session/agent.
  For now, we'll just keep it simple.
  """
  def authorized?(agent_id, action_module) do
    GenServer.call(__MODULE__, {:authorized?, agent_id, action_module})
  end

  @doc """
  Sets folder authorization for an agent.
  mode: :unrestricted | :whitelist | :blacklist
  paths: list of folder paths (relative to workspace root)
  """
  def set_folder_authorization(agent_id, mode, paths)
      when mode in [:unrestricted, :whitelist, :blacklist] do
    GenServer.call(__MODULE__, {:set_folder_auth, agent_id, mode, paths})
  end

  @doc """
  Gets folder authorization config for an agent.
  Returns %{mode: atom(), paths: MapSet.t()} or default unrestricted.
  """
  def get_folder_authorization(agent_id) do
    GenServer.call(__MODULE__, {:get_folder_auth, agent_id})
  end

  @doc """
  Adds a folder path to an agent's authorization list.
  Automatically switches mode to :whitelist if currently :unrestricted.
  """
  def add_authorized_folder(agent_id, folder_path) do
    GenServer.call(__MODULE__, {:add_folder, agent_id, folder_path})
  end

  @doc """
  Removes a folder path from an agent's authorization list.
  If no folders remain, reverts mode to :unrestricted.
  """
  def remove_authorized_folder(agent_id, folder_path) do
    GenServer.call(__MODULE__, {:remove_folder, agent_id, folder_path})
  end

  @doc """
  Lists all authorized folder paths for an agent.
  """
  def list_authorized_folders(agent_id) do
    GenServer.call(__MODULE__, {:list_folders, agent_id})
  end

  @doc """
  Checks if a resolved absolute path is within the agent's authorized folders.
  Returns :ok or {:error, :path_not_authorized}.
  """
  def check_folder_access(agent_id, resolved_path, project_root) do
    GenServer.call(__MODULE__, {:check_folder_access, agent_id, resolved_path, project_root})
  end

  @doc """
  Checks permission for an action.
  If authorized, returns :allowed.
  If not, tracks the request, broadcasts a signal, and returns {:ask_user, request_id}.
  """
  def check_permission(agent_id, action_module, params) do
    if authorized?(agent_id, action_module) do
      :allowed
    else
      request_id = "req_#{System.unique_integer([:positive, :monotonic])}"

      context = %{
        agent_id: agent_id,
        action_module: action_module,
        params: params,
        timestamp: DateTime.utc_now()
      }

      track_request(request_id, context)

      Cortex.SignalHub.emit(
        Cortex.SignalCatalog.permission_request(),
        %{
          provider: "system",
          event: "permission",
          action: "request",
          actor: "permission_tracker",
          origin: %{channel: "system", client: "permission_tracker", platform: "server"},
          request_id: request_id,
          agent_id: agent_id,
          action_module: inspect(action_module),
          params: params
        },
        source: "/system/permission_tracker"
      )

      {:ask_user, request_id}
    end
  end

  # Server Callbacks

  @impl true
  def init(_) do
    # State: %{
    #   requests: %{request_id => %{agent_id: id, action: action, status: :pending}},
    #   authorizations: %{agent_id => MapSet.new([action_module])},
    #   folder_authorizations: %{agent_id => %{mode: :unrestricted | :whitelist | :blacklist, paths: MapSet.t()}}
    # }
    {:ok, %{requests: %{}, authorizations: %{}, folder_authorizations: %{}}}
  end

  @impl true
  def handle_cast({:track_request, request_id, context}, state) do
    new_requests = Map.put(state.requests, request_id, Map.put(context, :status, :pending))
    {:noreply, %{state | requests: new_requests}}
  end

  @impl true
  def handle_cast({:resolve_request, request_id, decision}, state) do
    case Map.get(state.requests, request_id) do
      nil ->
        {:noreply, state}

      request ->
        new_requests = Map.delete(state.requests, request_id)

        state =
          if decision == :allow_always do
            agent_id = request.agent_id
            action_mod = request.action_module
            auths = Map.get(state.authorizations, agent_id, MapSet.new())
            new_auths = MapSet.put(auths, action_mod)
            %{state | authorizations: Map.put(state.authorizations, agent_id, new_auths)}
          else
            state
          end

        {:noreply, %{state | requests: new_requests}}
    end
  end

  @impl true
  def handle_call({:get_request, request_id}, _from, state) do
    {:reply, Map.get(state.requests, request_id), state}
  end

  @impl true
  def handle_call({:authorized?, agent_id, action_module}, _from, state) do
    auths = Map.get(state.authorizations, agent_id, MapSet.new())
    {:reply, MapSet.member?(auths, action_module), state}
  end

  @impl true
  def handle_call({:set_folder_auth, agent_id, mode, paths}, _from, state) do
    state = ensure_folder_authorizations(state)
    folder_auth = %{mode: mode, paths: MapSet.new(List.wrap(paths))}
    new_fa = Map.put(state.folder_authorizations, agent_id, folder_auth)
    {:reply, :ok, %{state | folder_authorizations: new_fa}}
  end

  @impl true
  def handle_call({:get_folder_auth, agent_id}, _from, state) do
    state = ensure_folder_authorizations(state)
    auth = Map.get(state.folder_authorizations, agent_id, %{mode: :unrestricted, paths: MapSet.new()})
    {:reply, auth, state}
  end

  @impl true
  def handle_call({:add_folder, agent_id, folder_path}, _from, state) do
    state = ensure_folder_authorizations(state)
    current = Map.get(state.folder_authorizations, agent_id, %{mode: :unrestricted, paths: MapSet.new()})
    new_mode = if current.mode == :unrestricted, do: :whitelist, else: current.mode
    normalized = String.trim_trailing(folder_path, "/")
    new_paths = MapSet.put(current.paths, normalized)
    new_fa = Map.put(state.folder_authorizations, agent_id, %{mode: new_mode, paths: new_paths})
    {:reply, :ok, %{state | folder_authorizations: new_fa}}
  end

  @impl true
  def handle_call({:remove_folder, agent_id, folder_path}, _from, state) do
    state = ensure_folder_authorizations(state)
    current = Map.get(state.folder_authorizations, agent_id, %{mode: :unrestricted, paths: MapSet.new()})
    normalized = String.trim_trailing(folder_path, "/")
    new_paths = MapSet.delete(current.paths, normalized)
    new_auth =
      if MapSet.size(new_paths) == 0,
        do: %{mode: :unrestricted, paths: new_paths},
        else: %{mode: current.mode, paths: new_paths}
    new_fa = Map.put(state.folder_authorizations, agent_id, new_auth)
    {:reply, :ok, %{state | folder_authorizations: new_fa}}
  end

  @impl true
  def handle_call({:list_folders, agent_id}, _from, state) do
    state = ensure_folder_authorizations(state)
    auth = Map.get(state.folder_authorizations, agent_id, %{mode: :unrestricted, paths: MapSet.new()})
    {:reply, MapSet.to_list(auth.paths), state}
  end

  @impl true
  def handle_call({:check_folder_access, agent_id, resolved_path, project_root}, _from, state) do
    state = ensure_folder_authorizations(state)
    auth = Map.get(state.folder_authorizations, agent_id, %{mode: :unrestricted, paths: MapSet.new()})
    result = do_check_folder_access(auth, resolved_path, project_root)
    {:reply, result, state}
  end

  defp ensure_folder_authorizations(%{folder_authorizations: _} = state), do: state
  defp ensure_folder_authorizations(state), do: Map.put(state, :folder_authorizations, %{})

  defp do_check_folder_access(%{mode: :unrestricted}, _path, _root), do: :ok

  defp do_check_folder_access(%{mode: :whitelist, paths: paths}, resolved_path, project_root) do
    relative = Path.relative_to(resolved_path, project_root)

    if path_in_folders?(relative, paths) do
      :ok
    else
      {:error, :path_not_authorized}
    end
  end

  defp do_check_folder_access(%{mode: :blacklist, paths: paths}, resolved_path, project_root) do
    relative = Path.relative_to(resolved_path, project_root)

    if path_in_folders?(relative, paths) do
      {:error, :path_not_authorized}
    else
      :ok
    end
  end

  defp path_in_folders?(relative_path, folders) do
    Enum.any?(folders, fn folder ->
      relative_path == folder or
        String.starts_with?(relative_path, folder <> "/")
    end)
  end
end
