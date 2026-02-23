defmodule Cortex.Workspaces.SnapshotManagerTest do
  use ExUnit.Case
  alias Cortex.Workspaces.SnapshotManager

  @backup_dir "backups"

  setup do
    # 清理备份目录
    File.rm_rf!(@backup_dir)
    on_exit(fn -> File.rm_rf!(@backup_dir) end)
    :ok
  end

  describe "backup_before_write/2" do
    test "creates a backup when file content changes" do
      # Setup initial file
      path = "test_file.txt"
      File.write!(path, "original content")
      on_exit(fn -> File.rm(path) end)

      new_content = "new content"

      {:ok, result} = SnapshotManager.backup_before_write(path, new_content)

      assert result.hash != nil
      assert File.exists?(result.backup_path)
      assert File.read!(result.backup_path) == "original content"
    end

    test "skips backup for new files" do
      path = "new_file.txt"
      if File.exists?(path), do: File.rm(path)

      assert {:ok, :no_backup_needed} = SnapshotManager.backup_before_write(path, "content")
    end

    test "skips backup if content is identical" do
      path = "test_file.txt"
      content = "same content"
      File.write!(path, content)
      on_exit(fn -> File.rm(path) end)

      assert {:ok, :no_backup_needed} = SnapshotManager.backup_before_write(path, content)
    end
  end

  describe "restore_from_backup/2" do
    test "restores file from backup path" do
      target_path = "target.txt"
      backup_content = "backup data"

      # Manually create a dummy backup file
      File.mkdir_p!(@backup_dir)
      backup_path = Path.join(@backup_dir, "test.bak")
      File.write!(backup_path, backup_content)

      {:ok, _} = SnapshotManager.restore_from_backup(backup_path, target_path)

      assert File.exists?(target_path)
      assert File.read!(target_path) == backup_content

      File.rm(target_path)
    end
  end
end
