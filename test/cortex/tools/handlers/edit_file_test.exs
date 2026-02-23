defmodule Cortex.Tools.Handlers.EditFileTest do
  use ExUnit.Case, async: true
  alias Cortex.Tools.Handlers.EditFile

  setup do
    session_id = "test_session_edit_#{System.unique_integer()}"

    tmp_dir = System.tmp_dir!() |> Path.join("jido_edit_test_#{System.unique_integer()}")
    File.mkdir_p!(tmp_dir)
    file_path = Path.join(tmp_dir, "test_edit.txt")
    File.write!(file_path, "Old Content")

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{session_id: session_id, file_path: file_path, tmp_dir: tmp_dir}
  end

  test "edits authorized file", %{session_id: session_id, file_path: file_path, tmp_dir: tmp_dir} do
    args = %{
      path: file_path,
      old_string: "Old Content",
      new_string: "New Content"
    }

    context = %{session_id: session_id, project_root: tmp_dir}

    assert {:ok, message} = EditFile.execute(args, context)
    assert message =~ "Successfully"
    assert File.read!(file_path) == "New Content"
  end

  test "edits authorized file with string keys", %{
    session_id: session_id,
    file_path: file_path,
    tmp_dir: tmp_dir
  } do
    args = %{
      "path" => file_path,
      "old_string" => "Old Content",
      "new_string" => "New Content"
    }

    context = %{session_id: session_id, project_root: tmp_dir}

    assert {:ok, message} = EditFile.execute(args, context)
    assert message =~ "Successfully"
    assert File.read!(file_path) == "New Content"
  end

  test "denies unauthorized file", %{session_id: session_id, tmp_dir: tmp_dir} do
    args = %{
      path: "/etc/passwd",
      old_string: "root",
      new_string: "hacker"
    }

    context = %{session_id: session_id, project_root: tmp_dir}

    assert {:error, {:permission_denied, reason}} = EditFile.execute(args, context)
    assert reason in [:path_escapes_boundary, :path_outside_boundary]
  end
end
