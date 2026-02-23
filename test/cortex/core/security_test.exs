defmodule Cortex.Core.SecurityTest do
  use ExUnit.Case, async: false

  alias Cortex.Core.Security

  setup do
    project_root =
      Path.expand(
        Path.join(System.tmp_dir!(), "jido_security_test_#{System.unique_integer([:positive])}")
      )

    File.mkdir_p!(project_root)

    # Set workspace root for protected file tests
    old_root = Application.get_env(:cortex, :workspace_root)
    Application.put_env(:cortex, :workspace_root, project_root)

    on_exit(fn ->
      File.rm_rf!(project_root)

      if old_root,
        do: Application.put_env(:cortex, :workspace_root, old_root),
        else: Application.delete_env(:cortex, :workspace_root)
    end)

    {:ok, project_root: project_root}
  end

  describe "validate_path/3" do
    test "allows valid paths within project root", %{project_root: project_root} do
      assert {:ok, resolved} = Security.validate_path("file.txt", project_root)
      assert resolved == Path.join(project_root, "file.txt")

      assert {:ok, resolved} = Security.validate_path("subdir/file.txt", project_root)
      assert resolved == Path.join(project_root, "subdir/file.txt")
    end

    test "allows relative paths with .. that stay within boundary", %{project_root: project_root} do
      assert {:ok, resolved} = Security.validate_path("subdir/../file.txt", project_root)
      assert resolved == Path.join(project_root, "file.txt")
    end

    test "blocks traversal attempts escaping boundary", %{project_root: project_root} do
      assert {:error, :path_escapes_boundary} =
               Security.validate_path("../outside.txt", project_root)

      assert {:error, :path_escapes_boundary} =
               Security.validate_path("subdir/../../outside.txt", project_root)
    end

    test "blocks absolute paths outside the boundary", %{project_root: project_root} do
      # Use a path that is definitely outside the project_root
      # Since project_root is a subdirectory of tmp_dir, tmp_dir itself is outside
      outside_path =
        Path.join(System.tmp_dir!(), "definitely_outside_#{System.unique_integer([:positive])}")

      assert {:error, :path_outside_boundary} = Security.validate_path(outside_path, project_root)
    end

    test "blocks URL-encoded traversal attempts", %{project_root: project_root} do
      assert {:error, :path_escapes_boundary} =
               Security.validate_path("%2e%2e/outside.txt", project_root)

      assert {:error, :path_escapes_boundary} =
               Security.validate_path("..%2foutside.txt", project_root)

      assert {:error, :path_escapes_boundary} =
               Security.validate_path("%2e%2e%2foutside.txt", project_root)
    end

    test "handles empty path by defaulting to project root", %{project_root: project_root} do
      assert {:ok, resolved} = Security.validate_path("", project_root)
      assert resolved == project_root
    end

    test "blocks protected settings files", %{project_root: project_root} do
      # We need to use a relative path that resolves to settings.json
      assert {:error, :protected_settings_file} =
               Security.validate_path("settings.json", project_root)

      assert {:error, :protected_settings_file} =
               Security.validate_path("./settings.json", project_root)
    end

    test "returns error for invalid inputs", %{project_root: project_root} do
      assert {:error, :invalid_path} = Security.validate_path(nil, project_root)
      assert {:error, :invalid_path} = Security.validate_path("file.txt", nil)
      assert {:error, :invalid_path} = Security.validate_path(123, project_root)
    end
  end

  describe "within_boundary?/2" do
    test "correctly identifies paths within or outside boundary" do
      root = "/app/project"
      assert Security.within_boundary?("/app/project/file.txt", root)
      assert Security.within_boundary?("/app/project", root)
      assert Security.within_boundary?("/app/project/", root)

      refute Security.within_boundary?("/app/other/file.txt", root)
      refute Security.within_boundary?("/app/project_extra/file.txt", root)
      refute Security.within_boundary?("/etc/passwd", root)
    end
  end

  describe "validate_cwd/2" do
    test "delegates to validate_path", %{project_root: project_root} do
      assert {:ok, _} = Security.validate_cwd("subdir", project_root)
      assert {:error, :path_escapes_boundary} = Security.validate_cwd("../", project_root)
    end
  end

  describe "atomic operations" do
    test "atomic_write and atomic_read work within boundary", %{project_root: project_root} do
      path = "test_atomic.txt"
      content = "hello atomic"

      assert :ok = Security.atomic_write(path, content, project_root)
      assert {:ok, ^content} = Security.atomic_read(path, project_root)
    end

    test "atomic operations block escaping paths", %{project_root: project_root} do
      path = "../escape.txt"

      assert {:error, :path_escapes_boundary} =
               Security.atomic_write(path, "content", project_root)

      assert {:error, :path_escapes_boundary} = Security.atomic_read(path, project_root)
    end
  end

  describe "symlink resolution and security" do
    test "allows symlink pointing inside boundary", %{project_root: project_root} do
      inner_dir = Path.join(project_root, "inner")
      File.mkdir_p!(inner_dir)
      target_file = Path.join(inner_dir, "target.txt")
      File.write!(target_file, "target content")

      symlink_path = Path.join(project_root, "safe_link")
      File.ln_s(target_file, symlink_path)

      assert {:ok, _} = Security.validate_path("safe_link", project_root)
      assert {:ok, "target content"} = Security.atomic_read("safe_link", project_root)
    end

    test "blocks symlink pointing outside boundary", %{project_root: project_root} do
      outside_file =
        Path.expand(
          Path.join(System.tmp_dir!(), "outside_#{System.unique_integer([:positive])}.txt")
        )

      File.write!(outside_file, "outside content")

      symlink_path = Path.join(project_root, "evil_link")
      File.ln_s(outside_file, symlink_path)

      assert {:error, :symlink_escapes_boundary} =
               Security.validate_path("evil_link", project_root)

      File.rm(outside_file)
    end

    test "detects symlink loops", %{project_root: project_root} do
      link1 = Path.join(project_root, "link1")
      link2 = Path.join(project_root, "link2")

      File.ln_s(link2, link1)
      File.ln_s(link1, link2)

      assert {:error, :invalid_path} = Security.validate_path("link1", project_root)
    end
  end

  describe "validate_realpath/3" do
    test "validates actual path on disk", %{project_root: project_root} do
      inner_file = Path.join(project_root, "inner.txt")
      File.write!(inner_file, "data")

      assert :ok = Security.validate_realpath(inner_file, project_root)

      outside_file =
        Path.expand(
          Path.join(System.tmp_dir!(), "outside_real_#{System.unique_integer([:positive])}.txt")
        )

      File.write!(outside_file, "data")

      assert {:error, :symlink_escapes_boundary} =
               Security.validate_realpath(outside_file, project_root)

      File.rm(outside_file)
    end
  end

  describe "validate_path_with_folders/3" do
    setup %{project_root: project_root} do
      # Ensure PermissionTracker is running
      case Process.whereis(Cortex.Core.PermissionTracker) do
        nil -> start_supervised!(Cortex.Core.PermissionTracker)
        _pid -> :ok
      end

      # Create test directories
      File.mkdir_p!(Path.join(project_root, "src"))
      File.mkdir_p!(Path.join(project_root, "docs"))
      File.write!(Path.join(project_root, "src/main.ex"), "defmodule Main do end")
      File.write!(Path.join(project_root, "docs/readme.md"), "# Readme")

      :ok
    end

    test "allows path when no agent_id provided", %{project_root: project_root} do
      assert {:ok, _} = Security.validate_path_with_folders("src/main.ex", project_root)
    end

    test "allows path in unrestricted mode", %{project_root: project_root} do
      agent_id = "sec_test_unr_#{System.unique_integer()}"
      assert {:ok, _} = Security.validate_path_with_folders("src/main.ex", project_root, agent_id: agent_id)
    end

    test "allows whitelisted path", %{project_root: project_root} do
      agent_id = "sec_test_wl_#{System.unique_integer()}"
      Cortex.Core.PermissionTracker.add_authorized_folder(agent_id, "src")
      assert {:ok, _} = Security.validate_path_with_folders("src/main.ex", project_root, agent_id: agent_id)
    end

    test "blocks non-whitelisted path", %{project_root: project_root} do
      agent_id = "sec_test_block_#{System.unique_integer()}"
      Cortex.Core.PermissionTracker.add_authorized_folder(agent_id, "src")
      assert {:error, :path_not_authorized} = Security.validate_path_with_folders("docs/readme.md", project_root, agent_id: agent_id)
    end

    test "still blocks path traversal even with folder auth", %{project_root: project_root} do
      agent_id = "sec_test_trav_#{System.unique_integer()}"
      Cortex.Core.PermissionTracker.add_authorized_folder(agent_id, "src")
      assert {:error, :path_escapes_boundary} = Security.validate_path_with_folders("../escape.txt", project_root, agent_id: agent_id)
    end
  end
end
