defmodule Cortex.Tools.Handlers.ReadFileTest do
  use ExUnit.Case, async: true
  alias Cortex.Tools.Handlers.ReadFile

  setup do
    session_id = "test_session_#{System.unique_integer()}"

    # Create a temp file
    tmp_dir = System.tmp_dir!() |> Path.join("jido_read_test_#{System.unique_integer()}")
    File.mkdir_p!(tmp_dir)
    file_path = Path.join(tmp_dir, "test_read.txt")
    File.write!(file_path, "Hello World")

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{session_id: session_id, file_path: file_path, tmp_dir: tmp_dir}
  end

  test "reads authorized file", %{session_id: session_id, file_path: file_path, tmp_dir: tmp_dir} do
    # In V3, path is authorized if it's within project_root
    args = %{path: file_path}
    context = %{session_id: session_id, project_root: tmp_dir}

    assert {:ok, content} = ReadFile.execute(args, context)
    assert String.contains?(content, "Hello World")
  end

  test "denies unauthorized file", %{
    session_id: session_id,
    file_path: _file_path,
    tmp_dir: tmp_dir
  } do
    # Try to read /etc/passwd or something outside tmp_dir
    args = %{path: "/etc/passwd"}
    context = %{session_id: session_id, project_root: tmp_dir}

    assert {:error, {:permission_denied, reason}} = ReadFile.execute(args, context)
    assert reason in [:path_escapes_boundary, :path_outside_boundary]
  end
end
