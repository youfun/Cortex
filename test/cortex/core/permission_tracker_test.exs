defmodule Cortex.Core.PermissionTrackerTest do
  use ExUnit.Case

  alias Cortex.Core.PermissionTracker
  alias Cortex.Actions.Files.Write

  setup do
    # Ensure PermissionTracker is running
    case Process.whereis(Cortex.Core.PermissionTracker) do
      nil -> start_supervised!(Cortex.Core.PermissionTracker)
      _pid -> :ok
    end

    :ok
  end

  test "tracks requests and resolves them" do
    agent_id = "test_agent_#{System.unique_integer()}"
    action = Write
    params = %{path: "test.txt", content: "foo"}

    # 1. Check permission - should be unauthorized initially
    assert {:ask_user, request_id} = PermissionTracker.check_permission(agent_id, action, params)

    # 2. Verify request is tracked
    request = PermissionTracker.get_request(request_id)
    assert request.agent_id == agent_id
    assert request.action_module == action
    assert request.status == :pending

    # 3. Resolve request (Allow)
    PermissionTracker.resolve_request(request_id, :allow)

    # Request should be removed (or status updated? implementation deletes it)
    assert nil == PermissionTracker.get_request(request_id)

    # But since it was just "allow" (one-time), it doesn't persist authorization for next time?
    # The implementation of resolve_request :allow doesn't update authorizations.
    # Only :allow_always updates authorizations.

    # Let's check authorized?
    refute PermissionTracker.authorized?(agent_id, action)
  end

  test "allow_always grants permanent permission" do
    agent_id = "test_agent_always_#{System.unique_integer()}"
    action = Write
    params = %{path: "test.txt", content: "foo"}

    # 1. Ask
    {:ask_user, request_id} = PermissionTracker.check_permission(agent_id, action, params)

    # 2. Allow Always
    PermissionTracker.resolve_request(request_id, :allow_always)

    # 3. Verify authorized
    assert PermissionTracker.authorized?(agent_id, action)

    # 4. Check permission again - should be :allowed
    assert :allowed == PermissionTracker.check_permission(agent_id, action, params)
  end

  test "deny simply removes the request" do
    agent_id = "test_agent_deny_#{System.unique_integer()}"
    action = Write
    params = %{path: "test.txt", content: "foo"}

    {:ask_user, request_id} = PermissionTracker.check_permission(agent_id, action, params)

    PermissionTracker.resolve_request(request_id, :deny)

    assert nil == PermissionTracker.get_request(request_id)
    refute PermissionTracker.authorized?(agent_id, action)
  end

  # ============================================================================
  # Folder Authorization Tests
  # ============================================================================

  describe "folder authorization" do
    test "default mode is unrestricted" do
      agent_id = "folder_test_#{System.unique_integer()}"
      auth = PermissionTracker.get_folder_authorization(agent_id)
      assert auth.mode == :unrestricted
      assert MapSet.size(auth.paths) == 0
    end

    test "add_authorized_folder switches to whitelist mode" do
      agent_id = "folder_add_#{System.unique_integer()}"
      assert :ok = PermissionTracker.add_authorized_folder(agent_id, "src")
      auth = PermissionTracker.get_folder_authorization(agent_id)
      assert auth.mode == :whitelist
      assert MapSet.member?(auth.paths, "src")
    end

    test "add multiple folders" do
      agent_id = "folder_multi_#{System.unique_integer()}"
      PermissionTracker.add_authorized_folder(agent_id, "src")
      PermissionTracker.add_authorized_folder(agent_id, "lib")
      folders = PermissionTracker.list_authorized_folders(agent_id)
      assert Enum.sort(folders) == ["lib", "src"]
    end

    test "remove folder reverts to unrestricted when empty" do
      agent_id = "folder_rm_#{System.unique_integer()}"
      PermissionTracker.add_authorized_folder(agent_id, "src")
      PermissionTracker.remove_authorized_folder(agent_id, "src")
      auth = PermissionTracker.get_folder_authorization(agent_id)
      assert auth.mode == :unrestricted
      assert MapSet.size(auth.paths) == 0
    end

    test "remove one folder keeps whitelist mode" do
      agent_id = "folder_rm2_#{System.unique_integer()}"
      PermissionTracker.add_authorized_folder(agent_id, "src")
      PermissionTracker.add_authorized_folder(agent_id, "lib")
      PermissionTracker.remove_authorized_folder(agent_id, "src")
      auth = PermissionTracker.get_folder_authorization(agent_id)
      assert auth.mode == :whitelist
      assert MapSet.to_list(auth.paths) == ["lib"]
    end

    test "set_folder_authorization with explicit mode" do
      agent_id = "folder_set_#{System.unique_integer()}"
      assert :ok = PermissionTracker.set_folder_authorization(agent_id, :blacklist, ["secrets", ".env"])
      auth = PermissionTracker.get_folder_authorization(agent_id)
      assert auth.mode == :blacklist
      assert MapSet.member?(auth.paths, "secrets")
      assert MapSet.member?(auth.paths, ".env")
    end

    test "check_folder_access allows all in unrestricted mode" do
      agent_id = "folder_check_unr_#{System.unique_integer()}"
      project_root = System.tmp_dir!()
      path = Path.join(project_root, "any/path/file.ex")
      assert :ok = PermissionTracker.check_folder_access(agent_id, path, project_root)
    end

    test "check_folder_access allows whitelisted path" do
      agent_id = "folder_check_wl_#{System.unique_integer()}"
      project_root = System.tmp_dir!()
      PermissionTracker.add_authorized_folder(agent_id, "src")
      path = Path.join(project_root, "src/main.ex")
      assert :ok = PermissionTracker.check_folder_access(agent_id, path, project_root)
    end

    test "check_folder_access blocks non-whitelisted path" do
      agent_id = "folder_check_block_#{System.unique_integer()}"
      project_root = System.tmp_dir!()
      PermissionTracker.add_authorized_folder(agent_id, "src")
      path = Path.join(project_root, "docs/readme.md")
      assert {:error, :path_not_authorized} = PermissionTracker.check_folder_access(agent_id, path, project_root)
    end

    test "check_folder_access allows exact folder match" do
      agent_id = "folder_check_exact_#{System.unique_integer()}"
      project_root = System.tmp_dir!()
      PermissionTracker.add_authorized_folder(agent_id, "src")
      path = Path.join(project_root, "src")
      assert :ok = PermissionTracker.check_folder_access(agent_id, path, project_root)
    end

    test "check_folder_access blocks in blacklist mode" do
      agent_id = "folder_check_bl_#{System.unique_integer()}"
      project_root = System.tmp_dir!()
      PermissionTracker.set_folder_authorization(agent_id, :blacklist, ["secrets"])
      path = Path.join(project_root, "secrets/key.pem")
      assert {:error, :path_not_authorized} = PermissionTracker.check_folder_access(agent_id, path, project_root)
    end

    test "check_folder_access allows non-blacklisted path" do
      agent_id = "folder_check_bl_ok_#{System.unique_integer()}"
      project_root = System.tmp_dir!()
      PermissionTracker.set_folder_authorization(agent_id, :blacklist, ["secrets"])
      path = Path.join(project_root, "src/main.ex")
      assert :ok = PermissionTracker.check_folder_access(agent_id, path, project_root)
    end

    test "trailing slash is normalized" do
      agent_id = "folder_slash_#{System.unique_integer()}"
      PermissionTracker.add_authorized_folder(agent_id, "src/")
      folders = PermissionTracker.list_authorized_folders(agent_id)
      assert folders == ["src"]
    end
  end
end
