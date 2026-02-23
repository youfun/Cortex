defmodule CortexWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use CortexWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint CortexWeb.Endpoint

      use CortexWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import CortexWeb.ConnCase
    end
  end

  setup tags do
    owner_pid = Cortex.DataCase.setup_sandbox(tags)
    Cortex.ProcessCase.ensure_test_processes()
    ensure_endpoint_started()
    Cortex.DataCase.allow_supervised_processes(owner_pid)
    {:ok, conn: Phoenix.ConnTest.build_conn(), owner_pid: owner_pid}
  end

  defp ensure_endpoint_started do
    case Process.whereis(CortexWeb.Endpoint) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        try do
          start_supervised!(CortexWeb.Endpoint)
          :ok
        rescue
          RuntimeError -> :ok
        end
    end
  end
end
