defmodule CortexWeb.SystemController do
  use CortexWeb, :controller
  require Logger

  def health(conn, _params) do
    json(conn, %{status: "ok", timestamp: DateTime.utc_now()})
  end

  def shutdown(conn, _params) do
    # Only allow shutdown from localhost
    if local_request?(conn) do
      Logger.info("========================================")
      Logger.info("Shutdown request received from localhost")
      Logger.info("Remote IP: #{inspect(conn.remote_ip)}")
      Logger.info("Request time: #{DateTime.utc_now()}")
      Logger.info("========================================")

      # Schedule shutdown in 100ms to allow response to be sent
      Task.start(fn ->
        Process.sleep(100)
        Logger.info("Initiating system halt...")
        Logger.info("All processes will be terminated")
        Logger.info("Stopping BEAM VM...")

        # Flush logger
        Logger.flush()

        # Burrito environment uses System.halt(0) (immediate termination of the VM)
        # Other environments use :init.stop() (graceful shutdown)
        if System.get_env("BURRITO_TARGET") do
          Logger.info("Burrito environment detected, using System.halt(0)")
          System.halt(0)
        else
          Logger.info("Standard environment, using :init.stop()")
          :init.stop()
        end
      end)

      Logger.info("Shutdown scheduled successfully")
      json(conn, %{status: "ok", message: "Shutting down..."})
    else
      Logger.warning("========================================")
      Logger.warning("SECURITY: Shutdown request DENIED")
      Logger.warning("Non-localhost IP: #{inspect(conn.remote_ip)}")
      Logger.warning("Request time: #{DateTime.utc_now()}")
      Logger.warning("========================================")

      conn
      |> put_status(:forbidden)
      |> json(%{error: "Forbidden"})
    end
  end

  defp local_request?(conn) do
    conn.remote_ip == {127, 0, 0, 1} or conn.remote_ip == {0, 0, 0, 0, 0, 0, 0, 1}
  end
end
