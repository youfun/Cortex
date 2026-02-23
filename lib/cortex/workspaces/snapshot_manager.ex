defmodule Cortex.Workspaces.SnapshotManager do
  @moduledoc """
  文件快照管理器 - 实现自动备份和撤销功能。

  功能：
  - 在文件写入前自动备份旧版本到 backups/HASH.bak
  - 提供 revert_edit(change_id) 接口从备份恢复物理文件
  - 基于 SHA256 哈希检测内容变化

  ## 使用示例

      iex> SnapshotManager.backup_before_write("/path/to/file.ex", "new content")
      {:ok, %{hash: "abc123...", backup_path: "backups/abc123.bak"}}

      iex> SnapshotManager.revert_edit(change_id)
      {:ok, "File restored from backup"}
  """

  require Logger
  alias Cortex.Coding
  alias Cortex.Workspaces

  @backup_dir "backups"
  @hash_algorithm :sha256

  @doc """
  在写入前创建文件备份。

  如果文件不存在或内容未变化，返回 :no_backup_needed。

  返回 {:ok, %{hash: hash, backup_path: path}} 或 {:error, reason}
  """
  def backup_before_write(file_path, new_content) do
    expanded_path = Path.expand(file_path)

    cond do
      not File.exists?(expanded_path) ->
        # 新文件，不需要备份
        {:ok, :no_backup_needed}

      true ->
        old_content = File.read!(expanded_path)
        old_hash = compute_hash(old_content)
        new_hash = compute_hash(new_content)

        if old_hash == new_hash do
          # 内容未变化
          {:ok, :no_backup_needed}
        else
          do_backup(expanded_path, old_content, old_hash)
        end
    end
  end

  @doc """
  撤销文件变更。

  根据 FileChange 记录从备份恢复文件。
  """
  def revert_edit(file_change_id) when is_binary(file_change_id) do
    case Coding.get_file_change!(file_change_id) do
      nil ->
        {:error, :file_change_not_found}

      file_change ->
        do_revert(file_change)
    end
  rescue
    Ecto.NoResultsError ->
      {:error, :file_change_not_found}
  end

  @doc """
  从备份路径恢复文件。
  """
  def restore_from_backup(backup_path, target_path) do
    expanded_backup = Path.expand(backup_path)
    expanded_target = Path.expand(target_path)

    if File.exists?(expanded_backup) do
      # 确保目标目录存在
      expanded_target
      |> Path.dirname()
      |> File.mkdir_p!()

      # 复制备份文件到目标位置
      case File.copy(expanded_backup, expanded_target) do
        {:ok, bytes} ->
          Logger.info(
            "[SnapshotManager] Restored #{expanded_target} from backup (#{bytes} bytes)"
          )

          {:ok, %{bytes_restored: bytes, target: expanded_target}}

        {:error, reason} ->
          {:error, {:copy_failed, reason}}
      end
    else
      {:error, :backup_not_found}
    end
  end

  @doc """
  计算内容的 SHA256 哈希值。
  """
  def compute_hash(content) when is_binary(content) do
    :crypto.hash(@hash_algorithm, content)
    |> Base.encode16(case: :lower)
  end

  @doc """
  清理过期的备份文件。

  默认保留最近 30 天的备份。
  """
  def cleanup_old_backups(opts \\ []) do
    max_age_days = Keyword.get(opts, :max_age_days, 30)
    backup_dir = Path.join(Workspaces.workspace_root(), @backup_dir)

    if File.exists?(backup_dir) do
      cutoff_time = DateTime.utc_now() |> DateTime.add(-max_age_days, :day)

      backup_dir
      |> File.ls!()
      |> Enum.filter(fn filename ->
        String.ends_with?(filename, ".bak")
      end)
      |> Enum.each(fn filename ->
        path = Path.join(backup_dir, filename)
        {:ok, stat} = File.stat(path)

        if DateTime.compare(stat.mtime, cutoff_time) == :lt do
          File.rm(path)
          Logger.info("[SnapshotManager] Cleaned up old backup: #{filename}")
        end
      end)

      :ok
    else
      :ok
    end
  end

  @doc """
  获取备份文件的完整路径。
  """
  def backup_path_for_hash(hash) do
    Path.join([Workspaces.workspace_root(), @backup_dir, "#{hash}.bak"])
  end

  # ========== Private Functions ==========

  defp do_backup(file_path, content, hash) do
    backup_dir = Path.join(Workspaces.workspace_root(), @backup_dir)
    backup_path = Path.join(backup_dir, "#{hash}.bak")

    # 确保备份目录存在
    File.mkdir_p!(backup_dir)

    # 写入备份文件
    case File.write(backup_path, content) do
      :ok ->
        Logger.info("[SnapshotManager] Backed up #{file_path} -> #{backup_path}")
        {:ok, %{hash: hash, backup_path: backup_path}}

      {:error, reason} ->
        {:error, {:backup_failed, reason}}
    end
  end

  defp do_revert(file_change) do
    cond do
      is_nil(file_change.backup_path) ->
        {:error, :no_backup_available}

      not File.exists?(file_change.backup_path) ->
        {:error, :backup_file_missing}

      true ->
        # 恢复文件
        target_path = file_change.file_path

        case restore_from_backup(file_change.backup_path, target_path) do
          {:ok, result} ->
            # 更新 FileChange 状态为已撤销
            case Coding.update_file_change(file_change, %{status: "reverted"}) do
              {:ok, _} -> {:ok, result}
              {:error, changeset} -> {:error, {:db_update_failed, changeset}}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end
end
