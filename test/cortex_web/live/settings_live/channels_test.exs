defmodule CortexWeb.SettingsLive.ChannelsTest do
  use CortexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    # Setup Basic Auth
    user = System.get_env("AUTH_USER", "admin")
    pass = System.get_env("AUTH_PASS", "admin")
    auth = "Basic " <> Base.encode64("#{user}:#{pass}")
    conn = put_req_header(conn, "authorization", auth)

    {:ok, conn: conn}
  end

  test "renders channel settings page without KeyError", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/settings/channels")
    assert html =~ "Channel Settings"
    assert html =~ "DingTalk"
  end
end
