defmodule Cortex.Core.Security do
  @moduledoc """
  Security boundary enforcement for tool operations.
  Ported from JidoCode.Tools.Security.
  """

  require Logger

  @type validation_error ::
          :path_escapes_boundary
          | :path_outside_boundary
          | :symlink_escapes_boundary
          | :protected_settings_file
          | :path_not_authorized
          | :invalid_path

  @type validate_opts :: [log_violations: boolean()]

  # URL-encoded path traversal patterns
  @url_encoded_traversal_patterns [
    "%2e%2e%2f",
    "%2e%2e/",
    "..%2f",
    "%2e%2e",
    "..%5c",
    "%2e%2e%5c",
    "%252e%252e%252f",
    "%252e%252e/",
    "%2E%2E%2F",
    "%2E%2E/"
  ]

  @doc """
  Validates that a path is within the project boundary.
  """
  @spec validate_path(String.t(), String.t(), validate_opts()) ::
          {:ok, String.t()} | {:error, validation_error()}
  def validate_path(path, project_root, opts \\ [])

  def validate_path(path, project_root, opts) when is_binary(path) and is_binary(project_root) do
    log_violations = Keyword.get(opts, :log_violations, true)
    normalized_path = if path == "", do: ".", else: path

    if contains_url_encoded_traversal?(normalized_path) do
      emit_security_telemetry(:path_escapes_boundary, path)
      maybe_log_violation(:path_escapes_boundary, path, log_violations)
      {:error, :path_escapes_boundary}
    else
      do_validate_path(normalized_path, project_root, log_violations)
    end
  end

  def validate_path(_, _, _), do: {:error, :invalid_path}

  @doc """
  Validates a working directory for shell commands.
  """
  @spec validate_cwd(String.t(), String.t()) :: {:ok, String.t()} | {:error, validation_error()}
  def validate_cwd(cwd, project_root) when is_binary(cwd) and is_binary(project_root) do
    validate_path(cwd, project_root)
  end

  @doc """
  Validates path within boundary AND checks folder-level authorization.
  Accepts :agent_id in opts to look up folder permissions from PermissionTracker.
  Falls back to standard validate_path when no agent_id is provided.
  """
  @spec validate_path_with_folders(String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, validation_error()}
  def validate_path_with_folders(path, project_root, opts \\ []) do
    agent_id = Keyword.get(opts, :agent_id)
    validate_opts = Keyword.take(opts, [:log_violations])

    with {:ok, safe_path} <- validate_path(path, project_root, validate_opts),
         :ok <- check_folder_authorization(safe_path, agent_id, project_root) do
      {:ok, safe_path}
    end
  end

  defp check_folder_authorization(_safe_path, nil, _root), do: :ok

  defp check_folder_authorization(safe_path, agent_id, project_root) do
    Cortex.Core.PermissionTracker.check_folder_access(agent_id, safe_path, project_root)
  end

  defp do_validate_path(path, project_root, log_violations) do
    normalized_root = normalize_path(project_root)

    resolved =
      case Path.type(path) do
        # On Windows, paths like "/etc/passwd" are :volumerelative and must be treated as
        # absolute-like for security. If we join them onto project_root we incorrectly
        # allow reads/writes under the boundary.
        :absolute -> normalize_path(path)
        :volumerelative -> normalize_path(path)
        _ -> normalize_path(Path.join(project_root, path))
      end

    if within_boundary?(resolved, normalized_root) do
      if is_protected_settings_file?(resolved) do
        emit_security_telemetry(:protected_settings_file, path)
        maybe_log_violation(:protected_settings_file, path, log_violations)
        {:error, :protected_settings_file}
      else
        check_symlinks(resolved, normalized_root, log_violations)
      end
    else
      reason = determine_violation_reason(path)
      emit_security_telemetry(reason, path)
      maybe_log_violation(reason, path, log_violations)
      {:error, reason}
    end
  end

  def within_boundary?(path, project_root) do
    normalized_path = normalize_path(path)
    normalized_root = normalize_path(project_root)

    String.starts_with?(normalized_path, normalized_root <> "/") or
      normalized_path == normalized_root
  end

  # --- Atomic Operations ---

  def atomic_read(path, project_root, opts \\ []) do
    case validate_path(path, project_root, opts) do
      {:ok, safe_path} ->
        case File.read(safe_path) do
          {:ok, content} ->
            case validate_realpath(safe_path, project_root, opts) do
              :ok -> {:ok, content}
              {:error, _} = error -> error
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, _} = error ->
        error
    end
  end

  def atomic_write(path, content, project_root, opts \\ []) do
    case validate_path(path, project_root, opts) do
      {:ok, safe_path} ->
        case safe_path |> Path.dirname() |> File.mkdir_p() do
          :ok ->
            case File.write(safe_path, content) do
              :ok -> validate_realpath(safe_path, project_root, opts)
              {:error, reason} -> {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, _} = error ->
        error
    end
  end

  def validate_realpath(path, project_root, opts \\ []) do
    log_violations = Keyword.get(opts, :log_violations, true)
    normalized_root = normalize_path(project_root)

    case :file.read_link_info(path, [:raw]) do
      {:ok, _info} ->
        case Path.expand(path) do
          expanded when is_binary(expanded) ->
            if within_boundary?(expanded, normalized_root) do
              :ok
            else
              maybe_log_violation(:symlink_escapes_boundary, path, log_violations)
              {:error, :symlink_escapes_boundary}
            end
        end

      {:error, :enoent} ->
        :ok

      {:error, _} ->
        :ok
    end
  end

  # --- Private Helpers ---

  defp contains_url_encoded_traversal?(path) do
    lower_path = String.downcase(path)
    Enum.any?(@url_encoded_traversal_patterns, &String.contains?(lower_path, &1))
  end

  defp is_protected_settings_file?(path) do
    root = Cortex.Workspaces.workspace_root() |> Path.expand()
    normalized_path = Path.expand(path)
    normalized_path == Path.join(root, "settings.json")
  end

  defp determine_violation_reason(path) do
    if Path.type(path) in [:absolute, :volumerelative],
      do: :path_outside_boundary,
      else: :path_escapes_boundary
  end

  defp maybe_log_violation(reason, path, true),
    do: Logger.warning("Security violation: #{reason} - attempted path: #{path}")

  defp maybe_log_violation(_, _, false), do: :ok

  defp emit_security_telemetry(violation_type, path) do
    :telemetry.execute(
      [:cortex, :security, :violation],
      %{count: 1},
      %{type: violation_type, path: sanitize_path_for_telemetry(path)}
    )
  end

  defp sanitize_path_for_telemetry(path) when byte_size(path) > 20 do
    "#{String.slice(path, 0, 8)}...#{String.slice(path, -8, 8)} (#{byte_size(path)} chars)"
  end

  defp sanitize_path_for_telemetry(path), do: path

  defp normalize_path(path), do: path |> Path.expand() |> String.trim_trailing("/")

  defp check_symlinks(path, project_root, log_violations) do
    case resolve_symlink_chain(path, project_root, MapSet.new()) do
      {:ok, final_path} ->
        {:ok, final_path}

      {:error, :symlink_escapes_boundary} = error ->
        if log_violations,
          do: Logger.warning("Security violation: symlink_escapes_boundary - path: #{path}")

        error

      {:error, :symlink_loop} ->
        if log_violations, do: Logger.warning("Security violation: symlink_loop - path: #{path}")
        {:error, :invalid_path}
    end
  end

  defp resolve_symlink_chain(path, project_root, seen) do
    if MapSet.member?(seen, path),
      do: {:error, :symlink_loop},
      else: resolve_symlink_target(path, project_root, seen)
  end

  defp resolve_symlink_target(path, project_root, seen) do
    case File.read_link(path) do
      {:ok, target} -> handle_symlink_target(path, target, project_root, seen)
      # Not a symlink or doesn't exist
      {:error, _} -> {:ok, path}
    end
  end

  defp handle_symlink_target(path, target, project_root, seen) do
    resolved_target = resolve_symlink_path(target, path)

    if within_boundary?(resolved_target, project_root) do
      resolve_symlink_chain(resolved_target, project_root, MapSet.put(seen, path))
    else
      {:error, :symlink_escapes_boundary}
    end
  end

  defp resolve_symlink_path(target, symlink_path) do
    if Path.type(target) == :absolute do
      normalize_path(target)
    else
      normalize_path(Path.join(Path.dirname(symlink_path), target))
    end
  end
end
